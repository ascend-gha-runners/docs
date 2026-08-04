#!/bin/bash
set -euo pipefail

# ==============================================================================
# CI 缓存审计脚本 — 基于 GitHub Actions 运行日志分析
#
# 优化策略（v2）：
#   1. GraphQL 查询替代 REST 翻页（获取 runs，1 次 GraphQL 替代 2-4 次 REST）
#   2. 早停：找到 MAX_CANDIDATES 个 NPU job 候选即停止扫描
#   3. 并发：repo 级 PARALLEL 并发处理
#
# 标记图例：
#   ✅ = confirmed in use（日志中找到缓存使用证据）
#   ❌ = confirmed NOT in use（日志中找到反面证据）
#   -  = unknown（无证据或无法确定）
#
# repos.txt 格式：
#   org/repo                           — 自动模式，GraphQL 查询
#   org/repo|workflow-file.yml         — 定向模式，REST 翻页搜指定 workflow
#
# 环境变量：
#   RUNNER_FILTER    — runner label 过滤词（逗号分隔），默认 "linux-aarch64,linux-amd64"
#   MAX_NPU_SEARCH   — 自动模式最多搜多少个 run，默认 50
#   MAX_CANDIDATES   — 早停：最多收集多少个候选 job，默认 3
#   PARALLEL         — 并发 repo 数，默认 4
#   PYPI_CACHE_HOST  — PyPI 缓存主机名
#   APT_CACHE_PORT   — APT 缓存端口
#   CCACHE_KEYWORD   — ccache 检测关键词（默认 "ccache"）
# ==============================================================================

if ! command -v jq &>/dev/null; then
    echo "Error: jq is not installed." >&2
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: gh (GitHub CLI) is not installed." >&2
    exit 1
fi

INPUT_FILE="${1:-}"
if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: $0 <repos_file>" >&2
    exit 1
fi

# ---------- Configuration ----------
PYPI_CACHE_HOST="${PYPI_CACHE_HOST:-cache-service.nginx-pypi-cache.svc.cluster.local}"
APT_CACHE_PORT="${APT_CACHE_PORT:-8081}"
APT_CACHE_HOST="${APT_CACHE_HOST:-}"
CCACHE_KEYWORD="${CCACHE_KEYWORD:-ccache}"
RUNNER_FILTER="${RUNNER_FILTER:-linux-aarch64,linux-amd64}"
MAX_NPU_SEARCH="${MAX_NPU_SEARCH:-50}"
MAX_CANDIDATES="${MAX_CANDIDATES:-3}"
PARALLEL="${PARALLEL:-4}"
PER_PAGE="${PER_PAGE:-30}"

RUNNER_REGEX=$(echo "$RUNNER_FILTER" | sed 's/,/|/g')

if [ -n "$APT_CACHE_HOST" ]; then
    APT_PATTERN="${APT_CACHE_HOST}"
else
    APT_PATTERN=":${APT_CACHE_PORT}"
fi

echo "Log-based Cache Audit Configuration (v2 — optimized):"
echo " - PyPI Cache Host:  $PYPI_CACHE_HOST"
echo " - APT Pattern:      $APT_PATTERN"
echo " - CCache Keyword:   $CCACHE_KEYWORD"
echo " - Runner Filter:    $RUNNER_FILTER (regex: $RUNNER_REGEX)"
echo " - Max NPU Search:   $MAX_NPU_SEARCH runs"
echo " - Max Candidates:   $MAX_CANDIDATES (early stop)"
echo " - Parallel:         $PARALLEL repos"
echo "------------------------------------------------------------------"

# ==============================================================================
# Phase 1 helpers: get runs and filter NPU jobs
# ==============================================================================

# GraphQL: get recent runs for a repo (replaces REST pagination)
# NOTE: GraphQL returns UPPERCASE enum values for conclusion/status
graphql_get_runs() {
    local REPO="$1"
    local ORG="${REPO%%/*}"
    local NAME="${REPO#*/}"

    gh api graphql \
        -f query='query($owner: String!, $name: String!) {
            repository(owner: $owner, name: $name) {
                workflowRuns(first: 30, orderBy: {field: CREATED_AT, direction: DESC}) {
                    nodes {
                        databaseId
                        headBranch
                        name
                        conclusion
                        status
                    }
                }
            }
        }' \
        -f owner="$ORG" \
        -f name="$NAME" \
        2>/dev/null \
    | jq -r '
        (.data.repository.workflowRuns.nodes // [])[]
        | select(.conclusion == "SUCCESS" or .conclusion == "FAILURE")
        | "\(.databaseId)|\(.headBranch)|\(.name)"
    ' 2>/dev/null || true
}

# REST fallback: get runs for a specific workflow file (when repos.txt specifies |workflow.yml)
rest_get_runs() {
    local REPO="$1"
    local WF="$2"
    local page=1
    local max_pages=$(( (MAX_NPU_SEARCH + PER_PAGE - 1) / PER_PAGE ))

    while [ "$page" -le "$max_pages" ]; do
        local runs_success runs_failure runs_json
        runs_success=$(gh api "repos/$REPO/actions/workflows/${WF}/runs?per_page=$PER_PAGE&page=$page&status=success" 2>/dev/null) || true
        runs_failure=$(gh api "repos/$REPO/actions/workflows/${WF}/runs?per_page=$PER_PAGE&page=$page&status=failure" 2>/dev/null) || true
        runs_json=$(echo "${runs_success}${runs_failure}" | jq -sc '
            {workflow_runs: ([.[].workflow_runs] | add // [] | sort_by(-.id))}
        ' 2>/dev/null) || true

        [ -z "$runs_json" ] && break
        local run_count
        run_count=$(echo "$runs_json" | jq -r '.workflow_runs | length' 2>/dev/null || echo "0")
        [ "$run_count" = "0" ] && break

        echo "$runs_json" | jq -r '.workflow_runs[] | "\(.id)|\(.head_branch)|\(.name)"'
        page=$((page + 1))
    done
}

# Get jobs for a run, filter NPU runner jobs
get_npu_jobs() {
    local REPO="$1"
    local RUN_ID="$2"

    local jobs_json
    jobs_json=$(gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" 2>/dev/null) || return 1

    echo "$jobs_json" | jq -r "
        .jobs[]
        | select(
            (.labels | any(test(\"$RUNNER_REGEX\"))) and
            .conclusion != \"skipped\" and
            .status == \"completed\"
          )
        | [.id, .name, (.labels | join(\",\"))] | join(\"|\")
    " 2>/dev/null || true
}

# ==============================================================================
# Phase 2: search log for cache evidence
# ==============================================================================
search_log_evidence() {
    local log_file="$1"
    # Sets via globals: repo_pypi repo_apt repo_ccache repo_uv
    # ev_pypi ev_apt ev_ccache ev_uv
    # counter_evidence_pypi counter_evidence_apt
    # counter_evidence_ccache counter_evidence_uv

    # Pre-check: skip jobs with no package installation activity
    if ! grep -qiE "pip install|apt-get install|apt install|uv install|uv pip|dnf install|yum install|rustup toolchain|cargo install|ccache|cmake|gcc|g\+\+|make|ninja" "$log_file" 2>/dev/null; then
        return 1
    fi

    # ---------- PyPI cache evidence ----------
    ev_pypi=""
    counter_evidence_pypi=""
    repo_pypi=false

    actual_index_line=$(grep -m1 -i "Looking in indexes" "$log_file" 2>/dev/null || true)
    if [ -n "$actual_index_line" ]; then
        if echo "$actual_index_line" | grep -q "$PYPI_CACHE_HOST"; then
            repo_pypi=true
            ev_pypi="pip实际用缓存: ${actual_index_line:0:200}"
        else
            counter_evidence_pypi="实际用: ${actual_index_line:0:200}"
        fi
    else
        grep_line=$(grep -m1 -iE "pip config set.*index-url" "$log_file" 2>/dev/null | grep "$PYPI_CACHE_HOST" || true)
        if [ -n "$grep_line" ]; then
            repo_pypi=true
            ev_pypi="uv/pip-config(配置,无运行时证据): ${grep_line:0:200}"
        fi
        if [ "$repo_pypi" = false ]; then
            grep_line=$(grep -m1 -E "PIP_INDEX_URL=.*$PYPI_CACHE_HOST|PIP_EXTRA_INDEX_URL=.*$PYPI_CACHE_HOST|UV_INDEX_URL=.*$PYPI_CACHE_HOST|UV_DEFAULT_INDEX=.*$PYPI_CACHE_HOST" "$log_file" 2>/dev/null || true)
            if [ -n "$grep_line" ]; then
                repo_pypi=true
                ev_pypi="pip/uv-env(配置,无运行时证据): ${grep_line:0:200}"
            fi
        fi
        if [ "$repo_pypi" = false ]; then
            grep_line=$(grep -m1 -iE "index-url|extra-index-url" "$log_file" 2>/dev/null | grep "$PYPI_CACHE_HOST" || true)
            if [ -n "$grep_line" ] && ! echo "$grep_line" | grep -qi "pip config set"; then
                repo_pypi=true
                ev_pypi="pip-config(配置,无运行时证据): ${grep_line:0:200}"
            fi
        fi
        if [ "$repo_pypi" = false ]; then
            grep_line=$(grep -m1 "$PYPI_CACHE_HOST" "$log_file" 2>/dev/null \
                | grep -viE "apt|sed|sources\.list|Get:|Hit:|Ign:" || true)
            if [ -n "$grep_line" ]; then
                repo_pypi=true
                ev_pypi="pip-broad(配置): ${grep_line:0:200}"
            fi
        fi
        # Counter-evidence: pip install with non-cache index
        if [ "$repo_pypi" = false ]; then
            grep_line=$(grep -m1 -iE "pip[3]? install |pip[3]? download " "$log_file" 2>/dev/null || true)
            if [ -n "$grep_line" ]; then
                counter_evidence_pypi="用pip但非缓存: ${grep_line:0:200}"
            fi
        fi
    fi

    # ---------- APT cache evidence ----------
    ev_apt=""
    counter_evidence_apt=""
    repo_apt=false

    grep_line=$(grep -m1 -iE "^Get:|^Hit:|^Ign:" "$log_file" 2>/dev/null | grep -E "$APT_PATTERN" || true)
    if [ -n "$grep_line" ]; then
        repo_apt=true
        ev_apt="apt-get: ${grep_line:0:200}"
    fi
    if [ "$repo_apt" = false ]; then
        grep_line=$(grep -m1 -i "Acquire::http" "$log_file" 2>/dev/null | grep -E "$APT_PATTERN" || true)
        if [ -n "$grep_line" ]; then
            repo_apt=true
            ev_apt="apt-proxy: ${grep_line:0:200}"
        fi
    fi
    if [ "$repo_apt" = false ]; then
        grep_line=$(grep -m1 -iE "sed.*${APT_PATTERN}" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            repo_apt=true
            ev_apt="apt-sed: ${grep_line:0:200}"
        fi
    fi
    if [ "$repo_apt" = false ]; then
        grep_line=$(grep -m1 -E "$APT_PATTERN" "$log_file" 2>/dev/null | grep -iE "apt|sources|mirror|repo" || true)
        if [ -n "$grep_line" ]; then
            repo_apt=true
            ev_apt="apt-broad: ${grep_line:0:200}"
        fi
    fi
    if [ "$repo_apt" = false ]; then
        grep_line=$(grep -m1 -iE "^Get:|^Hit:" "$log_file" 2>/dev/null | grep -vE "$APT_PATTERN|$PYPI_CACHE_HOST" || true)
        if [ -n "$grep_line" ]; then
            counter_evidence_apt="实际用: ${grep_line:0:200}"
        else
            grep_line=$(grep -m1 -iE "apt-get install|apt-get update" "$log_file" 2>/dev/null || true)
            if [ -n "$grep_line" ]; then
                counter_evidence_apt="apt cmd: ${grep_line:0:200}"
            fi
        fi
    fi

    # ---------- CCache evidence ----------
    ev_ccache=""
    counter_evidence_ccache=""
    repo_ccache=false

    grep_line=$(grep -m1 -iE "cache hit|cache miss|Cache hit|Cache miss|cache_hit|cache_miss|cachehit|cachemiss" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_ccache=true
        ev_ccache="ccache统计(运行时): ${grep_line:0:200}"
    fi
    if [ "$repo_ccache" = false ]; then
        grep_line=$(grep -m1 -iE "TRITON_BUILD_WITH_CCACHE|CMAKE_C_COMPILER_LAUNCHER.*ccache|CMAKE_CXX_COMPILER_LAUNCHER.*ccache|CC=ccache|CXX=ccache" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            repo_ccache=true
            ev_ccache="ccache-cmake(配置): ${grep_line:0:200}"
        fi
    fi
    if [ "$repo_ccache" = false ]; then
        grep_line=$(grep -m1 -iE "CCACHE_COMPRESS|CCACHE_DIR|ccache --zero-stats|ccache -z" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            repo_ccache=true
            ev_ccache="ccache-env(配置): ${grep_line:0:200}"
        fi
    fi
    if [ "$repo_ccache" = false ]; then
        grep_line=$(grep -m1 -iE "(^|[^a-z])ccache([^a-z]|$)" "$log_file" 2>/dev/null \
            | grep -viE "^\s*#|/usr/share/doc" || true)
        if [ -n "$grep_line" ]; then
            repo_ccache=true
            ev_ccache="ccache-broad: ${grep_line:0:200}"
        fi
    fi
    # Counter-evidence: compilation activity but no ccache
    if [ "$repo_ccache" = false ]; then
        grep_line=$(grep -m1 -iE "(^|[^a-z])(gcc|g\+\+|cmake --build|ninja|make)([^a-z]|$)" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            counter_evidence_ccache="编译活动无ccache: ${grep_line:0:200}"
        fi
    fi

    # ---------- uv evidence ----------
    ev_uv=""
    counter_evidence_uv=""
    repo_uv=false

    grep_line=$(grep -m1 -iE "^\s*uv (pip |sync|install|add|run pip)" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_uv=true
        ev_uv="uv-cmd(运行时): ${grep_line:0:200}"
    fi
    if [ "$repo_uv" = false ]; then
        grep_line=$(grep -m1 -iE "uv pip install|uv sync|uv install|Resolved .* packages|Prepared .* packages|Installed .* packages" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            repo_uv=true
            ev_uv="uv-output(运行时): ${grep_line:0:200}"
        fi
    fi
    if [ "$repo_uv" = false ]; then
        grep_line=$(grep -m1 -iE "UV_INDEX_URL|UV_DEFAULT_INDEX|UV_CACHE_DIR|pip install uv|pipx install uv|curl.*uv.*install|astral-sh/uv" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            repo_uv=true
            ev_uv="uv-setup(配置): ${grep_line:0:200}"
        fi
    fi
    # Counter-evidence: pip install but no uv
    if [ "$repo_uv" = false ]; then
        grep_line=$(grep -m1 -iE "pip[3]? install " "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            counter_evidence_uv="用pip非uv: ${grep_line:0:200}"
        fi
    fi

    return 0
}

# ==============================================================================
# Process one repo (Phase 1 + Phase 2)
# Output: writes markdown row to $OUTDIR/${safe}.row, stats to $OUTDIR/${safe}.stat
# ==============================================================================
process_repo() {
    local LINE="$1"
    local OUTDIR="$2"

    # Parse repo and optional workflow filter
    local REPO
    REPO=$(echo "$LINE" | cut -d'|' -f1 | xargs)
    local WORKFLOW_FILTER=""
    if [[ "$LINE" == *"|"* ]]; then
        WORKFLOW_FILTER=$(echo "$LINE" | cut -d'|' -f2 | xargs)
    fi

    local safe="${REPO//\//_}"
    local row_file="$OUTDIR/${safe}.row"
    local stat_file="$OUTDIR/${safe}.stat"
    local log_dir="$OUTDIR/logs_${safe}"
    mkdir -p "$log_dir"

    # Stats for this repo
    local s_pypi=0 s_apt=0 s_ccache=0 s_uv=0 s_no_cache=0 s_no_npu=0 s_error=0

    # ===== Phase 1: Collect candidates (max MAX_CANDIDATES) =====
    local candidates=""
    local candidate_count=0
    local runs_scanned=0
    local npu_found=false

    # Get runs: GraphQL (common) or REST (workflow filter fallback)
    local run_lines
    if [ -n "$WORKFLOW_FILTER" ]; then
        run_lines=$(rest_get_runs "$REPO" "$WORKFLOW_FILTER")
    else
        run_lines=$(graphql_get_runs "$REPO")
    fi

    # For each run, get jobs, find NPU candidates (early stop at MAX_CANDIDATES)
    while IFS='|' read -r run_id run_branch run_name; do
        [ -z "$run_id" ] && continue
        runs_scanned=$((runs_scanned + 1))

        # Safety cap
        [ "$runs_scanned" -gt "$MAX_NPU_SEARCH" ] && break

        local npu_jobs
        npu_jobs=$(get_npu_jobs "$REPO" "$run_id")

        if [ -n "$npu_jobs" ]; then
            npu_found=true
            while IFS='|' read -r job_id job_name job_labels; do
                [ -z "$job_id" ] && continue
                candidates="$candidates"$'\n'"$run_id|$run_branch|$run_name|$job_id|$job_name|$job_labels"
                candidate_count=$((candidate_count + 1))
                # Early stop: collected enough candidates
                [ "$candidate_count" -ge "$MAX_CANDIDATES" ] && break 2
            done <<< "$npu_jobs"
        fi
    done <<< "$run_lines"

    # ===== No NPU jobs found =====
    if [ "$candidate_count" -eq 0 ]; then
        local row=""
        if [ "$runs_scanned" -gt 0 ]; then
            row="| $REPO | (scanned $runs_scanned runs) | - | - | - | - | - | No NPU runner jobs found in last $runs_scanned runs |"
            s_no_npu=1
        else
            row="| $REPO | - | - | - | - | - | - | No completed runs / no access |"
            s_error=1
        fi
        echo "$row" > "$row_file"
        echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"
        rm -rf "$log_dir"
        return 0
    fi

    # ===== Phase 2: Try candidates one by one until a usable log is found =====
    local repo_pypi=false repo_apt=false repo_ccache=false repo_uv=false
    local ev_pypi="" ev_apt="" ev_ccache="" ev_uv=""
    local counter_evidence_pypi="" counter_evidence_apt=""
    local counter_evidence_ccache="" counter_evidence_uv=""
    local repo_run="" repo_runner="" repo_job_url=""
    local log_ok=false
    local log_no_pkg_activity=0

    # Deduplicate and sort candidates (newest run first)
    local sorted_candidates
    sorted_candidates=$(echo "$candidates" | grep -v '^$' | sort -t'|' -k1 -rn | uniq)

    while IFS='|' read -r c_run_id c_run_branch c_run_name c_job_id c_job_name c_job_labels; do
        [ -z "$c_job_id" ] && continue

        local log_file="$log_dir/${safe}_${c_run_id}_${c_job_id}.log"
        gh api "repos/$REPO/actions/jobs/$c_job_id/logs" >"$log_file" 2>/dev/null || {
            rm -f "$log_file"
            continue
        }

        if [ ! -s "$log_file" ]; then
            rm -f "$log_file"
            continue
        fi

        local file_size
        file_size=$(wc -c <"$log_file")
        if [ "$file_size" -lt 50 ]; then
            rm -f "$log_file"
            continue
        fi

        # Strip GitHub Actions log annotations, timestamps, and ANSI color codes
        sed -i 's/##\[group\]//g; s/##\[endgroup\]//g; s/##\[error\]//g; s/##\[warning\]//g; s/##\[notice\]//g; s/##\[command\]//g' "$log_file" 2>/dev/null || true
        sed -i 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\.[0-9]*Z //' "$log_file" 2>/dev/null || true
        sed -i 's/\x1b\[[0-9;]*m//g' "$log_file" 2>/dev/null || true

        # Search for evidence
        if ! search_log_evidence "$log_file"; then
            # Log downloaded OK but no package installation activity
            log_no_pkg_activity=1
            rm -f "$log_file"
            continue
        fi

        rm -f "$log_file"

        repo_run="${c_run_branch}/${c_run_name}"
        repo_runner="$c_job_labels"
        repo_job_url="https://github.com/${REPO}/actions/runs/${c_run_id}/job/${c_job_id}"
        log_ok=true
        break

    done <<< "$sorted_candidates"

    # ===== Output =====
    local row=""
    if [ "$log_ok" = false ]; then
        local first_candidate first_run_id first_job_id first_runner first_url
        first_candidate=$(echo "$sorted_candidates" | grep -v '^$' | head -1)
        first_run_id=$(echo "$first_candidate" | cut -d'|' -f1)
        first_job_id=$(echo "$first_candidate" | cut -d'|' -f4)
        first_runner=$(echo "$first_candidate" | cut -d'|' -f6)
        first_url="https://github.com/${REPO}/actions/runs/${first_run_id}/job/${first_job_id}"
        if [ "$log_no_pkg_activity" = 1 ]; then
            row="| $REPO | (NPU jobs found, no pkg activity) | $first_runner | - | - | - | - | NPU runner jobs found but no package installation in recent logs — [查看]($first_url) |"
        else
            row="| $REPO | (NPU jobs found, logs expired) | $first_runner | - | - | - | - | NPU runner jobs found but all logs expired (>90 days) — [查看]($first_url) |"
        fi
        s_error=1
        echo "$row" > "$row_file"
        echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"
        rm -rf "$log_dir"
        return 0
    fi

    local job_link="[日志](${repo_job_url})"

    # Determine marks
    local pypi_mark pypi_detail apt_mark apt_detail ccache_mark ccache_detail uv_mark uv_detail

    if [ "$repo_pypi" = true ]; then
        pypi_mark="✅"; pypi_detail="$ev_pypi"; s_pypi=1
    elif [ -n "$counter_evidence_pypi" ]; then
        pypi_mark="❌"; pypi_detail="反面证据: ${counter_evidence_pypi}"; s_no_cache=1
    else
        pypi_mark="-"; pypi_detail="无证据(日志中未出现 pip index 相关输出)"
    fi

    if [ "$repo_apt" = true ]; then
        apt_mark="✅"; apt_detail="$ev_apt"; s_apt=1
    elif [ -n "$counter_evidence_apt" ]; then
        apt_mark="❌"; apt_detail="反面证据: ${counter_evidence_apt}"; s_no_cache=1
    else
        apt_mark="-"; apt_detail="无证据(日志中未出现 apt Get/Hit 相关输出)"
    fi

    if [ "$repo_ccache" = true ]; then
        ccache_mark="✅"; ccache_detail="$ev_ccache"; s_ccache=1
    elif [ -n "$counter_evidence_ccache" ]; then
        ccache_mark="❌"; ccache_detail="反面证据: ${counter_evidence_ccache}"; s_no_cache=1
    else
        ccache_mark="-"; ccache_detail="无证据(日志中未出现 ccache 相关输出)"
    fi

    if [ "$repo_uv" = true ]; then
        uv_mark="✅"; uv_detail="$ev_uv"; s_uv=1
    elif [ -n "$counter_evidence_uv" ]; then
        uv_mark="❌"; uv_detail="反面证据: ${counter_evidence_uv}"; s_no_cache=1
    else
        uv_mark="-"; uv_detail="无证据(日志中未出现 uv 相关输出)"
    fi

    local evidence="${pypi_detail}; ${apt_detail}; ${ccache_detail}; ${uv_detail}"
    evidence="${evidence# ; }"
    evidence="${evidence% ; }"

    row="| $REPO | $repo_run | $repo_runner | $pypi_mark | $apt_mark | $ccache_mark | $uv_mark | ${evidence:0:400} $job_link |"
    echo "$row" > "$row_file"
    echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"

    rm -rf "$log_dir"
}

# ==============================================================================
# Main: read repos, process in parallel, combine results
# ==============================================================================

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TOTAL=0
REPO_LINES=()

# Read repos into array (preserve order)
while IFS= read -r LINE || [ -n "$LINE" ]; do
    [[ -z "$LINE" || "$LINE" =~ ^[[:space:]]*# ]] && continue
    REPO_LINES+=("$LINE")
    TOTAL=$((TOTAL + 1))
done < "$INPUT_FILE"

echo "Processing $TOTAL repos with $PARALLEL parallel workers..."
echo ""

# Output table header
echo "| 仓库 (Repository) | Run | Runner | PyPI 缓存 | APT 缓存 | CCache | uv | 证据 (Evidence) |"
echo "| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :--- |"

# Process repos in parallel
# Use background processes with a concurrency limit
declare -a PIDS=()
for line in "${REPO_LINES[@]}"; do
    process_repo "$line" "$TMPDIR" &
    PIDS+=($!)

    # Wait when we hit the concurrency limit
    if [ ${#PIDS[@]} -ge "$PARALLEL" ]; then
        wait "${PIDS[0]}" 2>/dev/null || true
        PIDS=("${PIDS[@]:1}")
    fi
done

# Wait for all remaining processes
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

# Combine results in original order
STAT_PYPI=0
STAT_APT=0
STAT_CCACHE=0
STAT_UV=0
STAT_NO_CACHE=0
STAT_NO_NPU=0
STAT_ERROR=0

for line in "${REPO_LINES[@]}"; do
    REPO=$(echo "$line" | cut -d'|' -f1 | xargs)
    safe="${REPO//\//_}"
    row_file="$TMPDIR/${safe}.row"
    stat_file="$TMPDIR/${safe}.stat"

    if [ -f "$row_file" ]; then
        cat "$row_file"
    else
        echo "| $REPO | - | - | - | - | - | - | Processing error — no output |"
        echo "0|0|0|0|0|0|1" > "$stat_file"
    fi

    if [ -f "$stat_file" ]; then
        IFS='|' read -r sp sa sc su sn snn se < "$stat_file"
        STAT_PYPI=$((STAT_PYPI + sp))
        STAT_APT=$((STAT_APT + sa))
        STAT_CCACHE=$((STAT_CCACHE + sc))
        STAT_UV=$((STAT_UV + su))
        STAT_NO_CACHE=$((STAT_NO_CACHE + sn))
        STAT_NO_NPU=$((STAT_NO_NPU + snn))
        STAT_ERROR=$((STAT_ERROR + se))
    fi
done

# ---------- Summary ----------
echo ""
echo "## Summary"
echo ""
echo "- Total repos checked: **$TOTAL**"
echo "- PyPI cache confirmed (✅): **$STAT_PYPI** / $TOTAL"
echo "- APT cache confirmed (✅): **$STAT_APT** / $TOTAL"
echo "- CCache confirmed (✅): **$STAT_CCACHE** / $TOTAL"
echo "- uv confirmed (✅): **$STAT_UV** / $TOTAL"
echo "- Confirmed NOT in use (❌): **$STAT_NO_CACHE** — need cache config"
echo "- No NPU runner jobs found: **$STAT_NO_NPU** — repos don't use our NPU runners"
echo "- Unknown / logs unavailable (-): **$STAT_ERROR**"
echo ""
echo "Audit complete."
