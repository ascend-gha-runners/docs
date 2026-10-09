#!/bin/bash
set -euo pipefail

# ==============================================================================
# CI 缓存审计脚本 — 基于 GitHub Actions 运行日志分析
#
# 优化策略（v4）：
#   1. GraphQL 查询替代 REST 翻页（获取 runs，1 次 GraphQL 替代 2-4 次 REST）
#   2. 候选收集：从 runs 中收集最多 MAX_CANDIDATES 个 NPU job 候选
#   3. 聚合证据：Phase 2 扫描多个候选日志，对每种缓存类型取"任一日志有正面证据→✅"
#   4. 并发：repo 级 PARALLEL 并发处理
#   5. 全量扫描：设 MAX_NPU_SEARCH=0 触发全量模式（内部 cap 200 runs + 30 candidates
#      + unlimited log aggregation），避免 API rate limit (5000/hr) 耗尽导致静默失败
#
# 标记图例：
#   ✅ = confirmed in use（日志或 workflow 中找到缓存使用证据）
#   ❌ = confirmed NOT in use（有反面证据且无正面证据）
#   -  = unknown（无证据或无法确定）
#
# 检测维度（7 列）：
#   PyPI / APT / CCache / uv —— 基于 job 日志
#   BuildKit —— workflow 静态扫（cache-from/cache-to/--import-cache/--export-cache/buildcache）
#               + 日志（=> CACHED / importing cache manifest / exporting cache）
#   Squid    —— 通用 HTTP 正向代理缓存（squid-cache / :3128），workflow 静态扫 + 日志
#   runs-on/cache —— runs-on 的 S3 后端 Actions 缓存（runs-on/cache@v5），workflow 静态扫 + 日志
#
# repos.txt 格式：
#   org/repo                           — 自动模式，GraphQL 查询
#   org/repo|workflow-file.yml         — 定向模式，REST 翻页搜指定 workflow
#   可选默认值列（第 3 列起）：pypi|apt|ccache|uv|buildkit|squid|runson
#
# 环境变量（设 0 = 全量模式，内部使用 cap 防止 rate limit）：
#   RUNNER_FILTER     — runner label 过滤词（逗号分隔），默认 "linux-aarch64,linux-amd64"
#   MAX_NPU_SEARCH    — 最多搜多少个 run，默认 50；0 = 全量模式（cap 200）
#   MAX_CANDIDATES    — Phase 1 最多收集多少个候选 job，默认 15；0 = 全量模式（cap 30）
#   MAX_LOGS_TO_CHECK — Phase 2 最多下载多少个候选日志做聚合，默认 10；0 = 无上限（全量聚合）
#   PARALLEL          — 并发 repo 数，默认 4
#   PYPI_CACHE_HOST   — PyPI 缓存主机名
#   APT_CACHE_PORT    — APT 缓存端口
#   CCACHE_KEYWORD    — ccache 检测关键词（默认 "ccache"）
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
# Squid 检测：squid 缓存，或真实代理端点 :3128（后面必须不是数字/冒号，
# 以排除 "block_sparse_attention_tiling.cpp:3128:22" 这类编译器 行:列 告警）
SQUID_PATTERN='squid-cache|:3128([^0-9:]|$)|HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy'
RUNNER_FILTER="${RUNNER_FILTER:-linux-aarch64,linux-amd64}"
MAX_NPU_SEARCH="${MAX_NPU_SEARCH:-50}"
MAX_CANDIDATES="${MAX_CANDIDATES:-15}"
MAX_LOGS_TO_CHECK="${MAX_LOGS_TO_CHECK:-10}"
PARALLEL="${PARALLEL:-4}"
PER_PAGE="${PER_PAGE:-30}"

RUNNER_REGEX=$(echo "$RUNNER_FILTER" | sed 's/,/|/g')

# Full scan mode: 0 means "use caps" (not unlimited) to prevent API rate limit exhaustion
# GitHub rate limit: 5000 req/hour. Scanning 2000+ runs per repo = 2000+ API calls,
# which exhausts the limit and causes get_npu_jobs() to silently return empty.
# Caps: 200 runs scan + 30 candidates + unlimited log aggregation = ~230 API calls/repo
FULL_SCAN_MODE=false
if [ "$MAX_NPU_SEARCH" = "0" ]; then
    FULL_SCAN_MODE=true
    MAX_NPU_SEARCH=200
fi
if [ "$MAX_CANDIDATES" = "0" ]; then
    MAX_CANDIDATES=30
fi
# MAX_LOGS_TO_CHECK=0 remains unlimited (log downloads don't use API rate limit)

if [ -n "$APT_CACHE_HOST" ]; then
    APT_PATTERN="${APT_CACHE_HOST}"
else
    APT_PATTERN=":${APT_CACHE_PORT}"
fi

echo "Log-based Cache Audit Configuration (v4 — optimized + aggregated):"
echo " - PyPI Cache Host:  $PYPI_CACHE_HOST"
echo " - APT Pattern:      $APT_PATTERN"
echo " - CCache Keyword:   $CCACHE_KEYWORD"
echo " - Runner Filter:    $RUNNER_FILTER (regex: $RUNNER_REGEX)"
if [ "$FULL_SCAN_MODE" = true ]; then
echo " - Mode:             FULL SCAN (capped at $MAX_NPU_SEARCH runs, $MAX_CANDIDATES candidates, unlimited logs)"
else
echo " - Max NPU Search:   $MAX_NPU_SEARCH runs"
echo " - Max Candidates:   $MAX_CANDIDATES"
fi
if [ "$MAX_LOGS_TO_CHECK" = "0" ]; then
echo " - Max Logs to Check: UNLIMITED (full aggregation)"
else
echo " - Max Logs to Check: $MAX_LOGS_TO_CHECK (aggregation)"
fi
echo " - Parallel:         $PARALLEL repos"
echo "------------------------------------------------------------------"

# ==============================================================================
# Phase 1 helpers: get runs and filter NPU jobs
# ==============================================================================

# Get recent runs for a repo (no workflow filter).
# NOTE: GitHub GraphQL has no `workflowRuns` field on `Repository`, so use REST instead.
graphql_get_runs() {
    local REPO="$1"
    rest_get_all_runs "$REPO" || true
    return 0
}

# REST: get runs for a repo (used in full scan mode, capped by MAX_NPU_SEARCH)
# Fetches success+failure runs with pagination, capped at max_pages
rest_get_all_runs() {
    local REPO="$1"
    local page=1
    local max_pages=$(( (MAX_NPU_SEARCH + 99) / 100 ))

    while [ "$page" -le "$max_pages" ]; do
        local runs_success runs_failure runs_json
        runs_success=$(gh api "repos/$REPO/actions/runs?per_page=100&page=$page&status=success" 2>/dev/null) || true
        runs_failure=$(gh api "repos/$REPO/actions/runs?per_page=100&page=$page&status=failure" 2>/dev/null) || true
        runs_json=$(printf '%s\n%s\n' "$runs_success" "$runs_failure" | jq -sc '
            {workflow_runs: ([.[].workflow_runs] | add // [] | sort_by(-.id))}
        ' 2>/dev/null) || true

        [ -z "$runs_json" ] && break
        local run_count
        run_count=$(echo "$runs_json" | jq -r '.workflow_runs | length' 2>/dev/null || echo "0")
        [ "$run_count" = "0" ] && break

        echo "$runs_json" | jq -r '.workflow_runs[] | "\(.id)|\(.head_branch)|\(.name)"' 2>/dev/null || true
        page=$((page + 1))
    done
}

# REST fallback: get runs for a specific workflow file (when repos.txt specifies |workflow.yml)
rest_get_runs() {
    local REPO="$1"
    local WF="$2"
    local page=1
    local max_pages
    max_pages=$(( (MAX_NPU_SEARCH + PER_PAGE - 1) / PER_PAGE ))

    while [ "$page" -le "$max_pages" ]; do
        local runs_success runs_failure runs_json
        runs_success=$(gh api "repos/$REPO/actions/workflows/${WF}/runs?per_page=$PER_PAGE&page=$page&status=success" 2>/dev/null) || true
        runs_failure=$(gh api "repos/$REPO/actions/workflows/${WF}/runs?per_page=$PER_PAGE&page=$page&status=failure" 2>/dev/null) || true
        runs_json=$(printf '%s\n%s\n' "$runs_success" "$runs_failure" | jq -sc '
            {workflow_runs: ([.[].workflow_runs] | add // [] | sort_by(-.id))}
        ' 2>/dev/null) || true

        [ -z "$runs_json" ] && break
        local run_count
        run_count=$(echo "$runs_json" | jq -r '.workflow_runs | length' 2>/dev/null || echo "0")
        [ "$run_count" = "0" ] && break

        echo "$runs_json" | jq -r '.workflow_runs[] | "\(.id)|\(.head_branch)|\(.name)"' 2>/dev/null || true
        page=$((page + 1))
    done
}

# Check GitHub API rate limit and sleep if running low
# Call before API-heavy operations to prevent silent failures
_api_calls_since_check=0
check_rate_limit() {
    _api_calls_since_check=$((_api_calls_since_check + 1))
    # Only check every 50 calls to avoid wasting API calls on rate_limit endpoint
    [ $((_api_calls_since_check % 50)) -ne 0 ] && return 0

    local remaining
    remaining=$(gh api rate_limit --jq '.rate.remaining' 2>/dev/null || echo "5000")
    if [ "$remaining" -lt 200 ]; then
        local reset_ts now_ts wait_sec
        reset_ts=$(gh api rate_limit --jq '.rate.reset' 2>/dev/null || echo "0")
        now_ts=$(date +%s)
        wait_sec=$((reset_ts - now_ts + 5))
        if [ "$wait_sec" -gt 0 ] && [ "$wait_sec" -lt 3600 ]; then
            echo "  [rate-limit] $remaining calls left, sleeping ${wait_sec}s..." >&2
            sleep "$wait_sec"
        fi
    fi
}

# Get jobs for a run, filter NPU runner jobs
# Includes retry logic for rate-limited requests
get_npu_jobs() {
    local REPO="$1"
    local RUN_ID="$2"

    check_rate_limit

    local jobs_json
    jobs_json=$(gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" 2>/dev/null) || return 0

    echo "$jobs_json" | jq -r "
        .jobs[]
        | select(
            (.labels | any(test(\"$RUNNER_REGEX\"))) and
            .conclusion != \"skipped\" and
            .status == \"completed\"
          )
        | [.id, .name, (.labels | join(\",\"))] | join(\"|\")
    " 2>/dev/null || true
    return 0
}

# ==============================================================================
# Static scan: read a repo's workflow YAML files for config-visible cache usage
# Sets globals: static_buildkit static_squid static_runson
#               static_ev_buildkit static_ev_squid static_ev_runson
# ==============================================================================
scan_workflows_static() {
    local REPO="$1"
    static_buildkit=false
    static_squid=false
    static_runson=false
    static_ev_buildkit=""
    static_ev_squid=""
    static_ev_runson=""

    local files
    files=$(gh api "repos/$REPO/contents/.github/workflows" --jq '.[].name' 2>/dev/null) || true
    if [ -z "$files" ]; then
        return 0
    fi

    local f content line
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in *.yml|*.yaml) ;; *) continue ;; esac
        content=$(gh api "repos/$REPO/contents/.github/workflows/$f" --jq '.content' 2>/dev/null \
            | tr -d '\n' | base64 -d 2>/dev/null) || true
        if [ -z "$content" ]; then
            continue
        fi

        if [ "$static_runson" = false ]; then
            line=$(printf '%s' "$content" | grep -m1 -E "runs-on/cache" 2>/dev/null) || true
            if [ -n "$line" ]; then
                static_runson=true
                static_ev_runson="workflow静态: ${line:0:200}"
            fi
        fi
        if [ "$static_buildkit" = false ]; then
            line=$(printf '%s' "$content" | grep -m1 -iE "cache-from|cache-to|--import-cache|--export-cache|buildcache|buildkit-cache" 2>/dev/null) || true
            if [ -n "$line" ]; then
                static_buildkit=true
                static_ev_buildkit="workflow静态: ${line:0:200}"
            fi
        fi
        if [ "$static_squid" = false ]; then
            line=$(printf '%s' "$content" | grep -m1 -iE "$SQUID_PATTERN" 2>/dev/null) || true
            if [ -n "$line" ]; then
                static_squid=true
                static_ev_squid="workflow静态: ${line:0:200}"
            fi
        fi
    done <<< "$files"
    return 0
}

# ==============================================================================
# Phase 2: search ONE log for cache evidence
# Sets globals: repo_pypi repo_apt repo_ccache repo_uv repo_buildkit repo_squid repo_runson
#               ev_pypi ev_apt ev_ccache ev_uv ev_buildkit ev_squid ev_runson
#               counter_evidence_pypi counter_evidence_apt
#               counter_evidence_ccache counter_evidence_uv
#               counter_evidence_buildkit counter_evidence_squid counter_evidence_runson
# Returns: 0 = log has package activity (evidence searched)
#          1 = log has no package activity (skip)
# ==============================================================================
search_log_evidence() {
    local log_file="$1"

    # Pre-check: skip jobs with no package installation / cache activity
    if ! grep -qiE "pip install|apt-get install|apt install|uv install|uv pip|dnf install|yum install|rustup toolchain|cargo install|ccache|cmake|gcc|g\+\+|make|ninja|buildctl|build-push|cache-from|cache-to|import-cache|export-cache|buildcache|buildkit|docker build|$SQUID_PATTERN|runs-on/cache|Cache restored|Cache saved" "$log_file" 2>/dev/null; then
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

    # ---------- BuildKit cache evidence ----------
    ev_buildkit=""
    counter_evidence_buildkit=""
    repo_buildkit=false

    grep_line=$(grep -m1 -iE "cache-from|cache-to|--import-cache|--export-cache|importing cache manifest|exporting cache|=> CACHED|CACHED \[|buildcache|buildkit-cache" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_buildkit=true
        ev_buildkit="buildkit-cache(运行时/配置): ${grep_line:0:200}"
    fi
    # Counter-evidence: uses buildkit but no cache instruction
    if [ "$repo_buildkit" = false ]; then
        grep_line=$(grep -m1 -iE "BUILDKITD_ADDR|buildctl|buildkitd" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            counter_evidence_buildkit="用buildkit但无缓存指令: ${grep_line:0:200}"
        fi
    fi

    # ---------- Squid proxy evidence ----------
    ev_squid=""
    counter_evidence_squid=""
    repo_squid=false

    grep_line=$(grep -m1 -iE "$SQUID_PATTERN" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_squid=true
        ev_squid="squid代理: ${grep_line:0:200}"
    fi

    # ---------- runs-on/cache evidence ----------
    ev_runson=""
    counter_evidence_runson=""
    repo_runson=false

    grep_line=$(grep -m1 -iE "runs-on/cache|Cache restored from key|Cache saved with key|Cache not found for input keys" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_runson=true
        ev_runson="runs-on/cache(运行时): ${grep_line:0:200}"
    fi
    # Counter-evidence: uses actions/cache instead of runs-on/cache
    if [ "$repo_runson" = false ]; then
        grep_line=$(grep -m1 -E "actions/cache@|actions/cache/" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            counter_evidence_runson="用 actions/cache 而非 runs-on/cache: ${grep_line:0:200}"
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
    local s_pypi=0 s_apt=0 s_ccache=0 s_uv=0 s_buildkit=0 s_squid=0 s_runson=0
    local s_no_cache=0 s_no_npu=0 s_error=0

    # Static scan of workflow files (config-visible evidence for BuildKit / Squid / runs-on cache)
    scan_workflows_static "$REPO" || true

    # ===== Phase 1: Collect candidates (up to MAX_CANDIDATES) =====
    local candidates=""
    local candidate_count=0
    local runs_scanned=0
    local npu_found=false

    # Get runs: GraphQL (common) or REST (workflow filter fallback)
    # NOTE: || true needed because set -e would kill the background process
    local run_lines
    if [ -n "$WORKFLOW_FILTER" ]; then
        run_lines=$(rest_get_runs "$REPO" "$WORKFLOW_FILTER") || run_lines=""
    else
        run_lines=$(graphql_get_runs "$REPO") || run_lines=""
    fi

    # For each run, get jobs, find NPU candidates (stop at MAX_CANDIDATES)
    while IFS='|' read -r run_id run_branch run_name; do
        [ -z "$run_id" ] && continue
        runs_scanned=$((runs_scanned + 1))

        # Safety cap (0 = unlimited)
        [ "$MAX_NPU_SEARCH" -gt 0 ] && [ "$runs_scanned" -gt "$MAX_NPU_SEARCH" ] && break

        local npu_jobs
        npu_jobs=$(get_npu_jobs "$REPO" "$run_id") || npu_jobs=""

        if [ -n "$npu_jobs" ]; then
            npu_found=true
            while IFS='|' read -r job_id job_name job_labels; do
                [ -z "$job_id" ] && continue
                candidates="$candidates"$'\n'"$run_id|$run_branch|$run_name|$job_id|$job_name|$job_labels"
                candidate_count=$((candidate_count + 1))
                # Stop collecting once we have enough candidates (0 = unlimited)
                [ "$MAX_CANDIDATES" -gt 0 ] && [ "$candidate_count" -ge "$MAX_CANDIDATES" ] && break 2
            done <<< "$npu_jobs"
        fi
    done <<< "$run_lines"

    # ===== No NPU jobs found =====
    if [ "$candidate_count" -eq 0 ]; then
        local row=""
        if [ "$runs_scanned" -gt 0 ]; then
            row="| $REPO | (scanned $runs_scanned runs) | - | - | - | - | - | - | - | - | No NPU runner jobs found in last $runs_scanned runs |"
            s_no_npu=1
        else
            row="| $REPO | - | - | - | - | - | - | - | - | - | No completed runs / no access |"
            s_error=1
        fi
        echo "$row" > "$row_file"
        echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_buildkit|$s_squid|$s_runson|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"
        rm -rf "$log_dir"
        return 0
    fi

    # ===== Phase 2: Aggregate evidence from multiple candidate logs =====
    # For each cache type:
    #   ✅ = ANY log has positive evidence
    #   ❌ = NO log has positive evidence AND ANY log has counter-evidence
    #   -  = otherwise (no evidence in any direction)
    local agg_pypi=false agg_apt=false agg_ccache=false agg_uv=false
    local agg_buildkit=false agg_squid=false agg_runson=false
    local agg_ev_pypi="" agg_ev_apt="" agg_ev_ccache="" agg_ev_uv=""
    local agg_ev_buildkit="" agg_ev_squid="" agg_ev_runson=""
    local agg_counter_pypi="" agg_counter_apt="" agg_counter_ccache="" agg_counter_uv=""
    local agg_counter_buildkit="" agg_counter_squid="" agg_counter_runson=""
    local logs_checked=0
    local log_no_pkg_activity=0
    local repo_run="" repo_runner="" repo_job_url=""

    # Deduplicate and sort candidates (newest run first)
    local sorted_candidates
    sorted_candidates=$(echo "$candidates" | grep -v '^$' | sort -t'|' -k1 -rn | uniq) || sorted_candidates=""

    while IFS='|' read -r c_run_id c_run_branch c_run_name c_job_id c_job_name c_job_labels; do
        [ -z "$c_job_id" ] && continue

        # Limit how many logs we download for aggregation (0 = unlimited)
        [ "$MAX_LOGS_TO_CHECK" -gt 0 ] && [ "$logs_checked" -ge "$MAX_LOGS_TO_CHECK" ] && break

        local log_file="$log_dir/${safe}_${c_run_id}_${c_job_id}.log"
        local log_stderr="$log_dir/gh_api_stderr.log"
        curl -fsSL -H "Authorization: Bearer $GH_TOKEN" \
            "https://api.github.com/repos/$REPO/actions/jobs/$c_job_id/logs" \
            >"$log_file" 2>"$log_stderr" || {
            echo "  [log download failed] $REPO job=$c_job_id:" >&2
            cat "$log_stderr" >&2 2>/dev/null || true
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

        # Search for evidence in this log
        if ! search_log_evidence "$log_file"; then
            # Log downloaded OK but no package installation activity
            log_no_pkg_activity=1
            rm -f "$log_file"
            continue
        fi

        rm -f "$log_file"

        # This log has package activity — aggregate evidence
        logs_checked=$((logs_checked + 1))

        # Record first usable log's metadata (for the output row)
        if [ "$logs_checked" = 1 ]; then
            repo_run="${c_run_branch}/${c_run_name}"
            repo_runner="$c_job_labels"
            repo_job_url="https://github.com/${REPO}/actions/runs/${c_run_id}/job/${c_job_id}"
        fi

        # Aggregate positive evidence (take first found for each type)
        if [ "$repo_pypi" = true ] && [ "$agg_pypi" = false ]; then
            agg_pypi=true
            agg_ev_pypi="$ev_pypi"
        fi
        if [ "$repo_apt" = true ] && [ "$agg_apt" = false ]; then
            agg_apt=true
            agg_ev_apt="$ev_apt"
        fi
        if [ "$repo_ccache" = true ] && [ "$agg_ccache" = false ]; then
            agg_ccache=true
            agg_ev_ccache="$ev_ccache"
        fi
        if [ "$repo_uv" = true ] && [ "$agg_uv" = false ]; then
            agg_uv=true
            agg_ev_uv="$ev_uv"
        fi
        if [ "$repo_buildkit" = true ] && [ "$agg_buildkit" = false ]; then
            agg_buildkit=true
            agg_ev_buildkit="$ev_buildkit"
        fi
        if [ "$repo_squid" = true ] && [ "$agg_squid" = false ]; then
            agg_squid=true
            agg_ev_squid="$ev_squid"
        fi
        if [ "$repo_runson" = true ] && [ "$agg_runson" = false ]; then
            agg_runson=true
            agg_ev_runson="$ev_runson"
        fi

        # Aggregate counter-evidence (take first found, only if no positive yet)
        if [ "$repo_pypi" = false ] && [ -n "$counter_evidence_pypi" ] && [ -z "$agg_counter_pypi" ]; then
            agg_counter_pypi="$counter_evidence_pypi"
        fi
        if [ "$repo_apt" = false ] && [ -n "$counter_evidence_apt" ] && [ -z "$agg_counter_apt" ]; then
            agg_counter_apt="$counter_evidence_apt"
        fi
        if [ "$repo_ccache" = false ] && [ -n "$counter_evidence_ccache" ] && [ -z "$agg_counter_ccache" ]; then
            agg_counter_ccache="$counter_evidence_ccache"
        fi
        if [ "$repo_uv" = false ] && [ -n "$counter_evidence_uv" ] && [ -z "$agg_counter_uv" ]; then
            agg_counter_uv="$counter_evidence_uv"
        fi
        if [ "$repo_buildkit" = false ] && [ -n "$counter_evidence_buildkit" ] && [ -z "$agg_counter_buildkit" ]; then
            agg_counter_buildkit="$counter_evidence_buildkit"
        fi
        if [ "$repo_squid" = false ] && [ -n "$counter_evidence_squid" ] && [ -z "$agg_counter_squid" ]; then
            agg_counter_squid="$counter_evidence_squid"
        fi
        if [ "$repo_runson" = false ] && [ -n "$counter_evidence_runson" ] && [ -z "$agg_counter_runson" ]; then
            agg_counter_runson="$counter_evidence_runson"
        fi

        # Early exit: all 7 cache types have positive evidence, no need to check more logs
        if [ "$agg_pypi" = true ] && [ "$agg_apt" = true ] && [ "$agg_ccache" = true ] && [ "$agg_uv" = true ] \
           && [ "$agg_buildkit" = true ] && [ "$agg_squid" = true ] && [ "$agg_runson" = true ]; then
            break
        fi

    done <<< "$sorted_candidates"

    # ===== Output =====
    local row=""
    if [ "$logs_checked" -eq 0 ]; then
        # No usable logs found (download failed/empty or no package activity)
        local first_candidate first_run_id first_job_id first_runner first_url
        first_candidate=$(echo "$sorted_candidates" | grep -v '^$' | head -1)
        first_run_id=$(echo "$first_candidate" | cut -d'|' -f1)
        first_job_id=$(echo "$first_candidate" | cut -d'|' -f4)
        first_runner=$(echo "$first_candidate" | cut -d'|' -f6)
        first_url="https://github.com/${REPO}/actions/runs/${first_run_id}/job/${first_job_id}"
        # Apply static (workflow) evidence for the 3 config-visible dims even without pkg activity
        local nb_mark ns_mark nr_mark
        nb_mark="-"; ns_mark="-"; nr_mark="-"
        if [ "$static_buildkit" = true ]; then nb_mark="✅"; s_buildkit=1; fi
        if [ "$static_squid" = true ]; then ns_mark="✅"; s_squid=1; fi
        if [ "$static_runson" = true ]; then nr_mark="✅"; s_runson=1; fi
        if [ "$log_no_pkg_activity" = 1 ]; then
            row="| $REPO | (NPU jobs found, no pkg activity) | $first_runner | - | - | - | - | $nb_mark | $ns_mark | $nr_mark | NPU runner jobs found but no package installation in recent logs — [查看]($first_url) |"
        else
            row="| $REPO | (NPU jobs found, log download failed) | $first_runner | - | - | - | - | $nb_mark | $ns_mark | $nr_mark | NPU runner jobs found but logs could not be downloaded (expired or fetch failed) — [查看]($first_url) |"
        fi
        s_error=1
        echo "$row" > "$row_file"
        echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_buildkit|$s_squid|$s_runson|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"
        rm -rf "$log_dir"
        return 0
    fi

    local job_link="[日志](${repo_job_url})"

    # Determine marks based on aggregated evidence
    local pypi_mark pypi_detail apt_mark apt_detail ccache_mark ccache_detail uv_mark uv_detail
    local buildkit_mark buildkit_detail squid_mark squid_detail runson_mark runson_detail

    if [ "$agg_pypi" = true ]; then
        pypi_mark="✅"; pypi_detail="$agg_ev_pypi"; s_pypi=1
    elif [ -n "$agg_counter_pypi" ]; then
        pypi_mark="❌"; pypi_detail="反面证据: ${agg_counter_pypi}"; s_no_cache=1
    else
        pypi_mark="-"; pypi_detail="无证据(日志中未出现 pip index 相关输出)"
    fi

    if [ "$agg_apt" = true ]; then
        apt_mark="✅"; apt_detail="$agg_ev_apt"; s_apt=1
    elif [ -n "$agg_counter_apt" ]; then
        apt_mark="❌"; apt_detail="反面证据: ${agg_counter_apt}"; s_no_cache=1
    else
        apt_mark="-"; apt_detail="无证据(日志中未出现 apt Get/Hit 相关输出)"
    fi

    if [ "$agg_ccache" = true ]; then
        ccache_mark="✅"; ccache_detail="$agg_ev_ccache"; s_ccache=1
    elif [ -n "$agg_counter_ccache" ]; then
        ccache_mark="❌"; ccache_detail="反面证据: ${agg_counter_ccache}"; s_no_cache=1
    else
        ccache_mark="-"; ccache_detail="无证据(日志中未出现 ccache 相关输出)"
    fi

    if [ "$agg_uv" = true ]; then
        uv_mark="✅"; uv_detail="$agg_ev_uv"; s_uv=1
    elif [ -n "$agg_counter_uv" ]; then
        uv_mark="❌"; uv_detail="反面证据: ${agg_counter_uv}"; s_no_cache=1
    else
        uv_mark="-"; uv_detail="无证据(日志中未出现 uv 相关输出)"
    fi

    # BuildKit: workflow 静态证据优先，其次日志
    if [ "$static_buildkit" = true ]; then
        buildkit_mark="✅"; buildkit_detail="$static_ev_buildkit"; s_buildkit=1
    elif [ "$agg_buildkit" = true ]; then
        buildkit_mark="✅"; buildkit_detail="$agg_ev_buildkit"; s_buildkit=1
    elif [ -n "$agg_counter_buildkit" ]; then
        buildkit_mark="❌"; buildkit_detail="反面证据: ${agg_counter_buildkit}"; s_no_cache=1
    else
        buildkit_mark="-"; buildkit_detail="无证据(日志/workflow 中未出现 buildkit 缓存指令)"
    fi

    # Squid: workflow 静态证据优先，其次日志
    if [ "$static_squid" = true ]; then
        squid_mark="✅"; squid_detail="$static_ev_squid"; s_squid=1
    elif [ "$agg_squid" = true ]; then
        squid_mark="✅"; squid_detail="$agg_ev_squid"; s_squid=1
    elif [ -n "$agg_counter_squid" ]; then
        squid_mark="❌"; squid_detail="反面证据: ${agg_counter_squid}"; s_no_cache=1
    else
        squid_mark="-"; squid_detail="无证据(日志/workflow 中未出现 squid 代理地址)"
    fi

    # runs-on/cache: workflow 静态证据优先，其次日志
    if [ "$static_runson" = true ]; then
        runson_mark="✅"; runson_detail="$static_ev_runson"; s_runson=1
    elif [ "$agg_runson" = true ]; then
        runson_mark="✅"; runson_detail="$agg_ev_runson"; s_runson=1
    elif [ -n "$agg_counter_runson" ]; then
        runson_mark="❌"; runson_detail="反面证据: ${agg_counter_runson}"; s_no_cache=1
    else
        runson_mark="-"; runson_detail="无证据(日志/workflow 中未出现 runs-on/cache)"
    fi

    local evidence="${pypi_detail}; ${apt_detail}; ${ccache_detail}; ${uv_detail}; ${buildkit_detail}; ${squid_detail}; ${runson_detail}"
    evidence="${evidence# ; }"
    evidence="${evidence% ; }"
    # Sanitize: replace pipe chars to prevent markdown table column corruption
    evidence="${evidence//|/¦}"

    row="| $REPO | $repo_run | $repo_runner | $pypi_mark | $apt_mark | $ccache_mark | $uv_mark | $buildkit_mark | $squid_mark | $runson_mark | ${evidence:0:400} $job_link |"
    echo "$row" > "$row_file"
    echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_buildkit|$s_squid|$s_runson|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"

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
echo "| 仓库 (Repository) | Run | Runner | PyPI 缓存 | APT 缓存 | CCache | uv | BuildKit | Squid | runs-on/cache | 证据 (Evidence) |"
echo "| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |"

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
STAT_BUILDKIT=0
STAT_SQUID=0
STAT_RUNSON=0
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
        echo "| $REPO | - | - | - | - | - | - | - | - | - | Processing error — no output |"
        echo "0|0|0|0|0|0|0|0|0|1" > "$stat_file"
    fi

    if [ -f "$stat_file" ]; then
        IFS='|' read -r sp sa sc su sbk ssq srs sn snn se < "$stat_file"
        STAT_PYPI=$((STAT_PYPI + sp))
        STAT_APT=$((STAT_APT + sa))
        STAT_CCACHE=$((STAT_CCACHE + sc))
        STAT_UV=$((STAT_UV + su))
        STAT_BUILDKIT=$((STAT_BUILDKIT + sbk))
        STAT_SQUID=$((STAT_SQUID + ssq))
        STAT_RUNSON=$((STAT_RUNSON + srs))
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
echo "- BuildKit cache confirmed (✅): **$STAT_BUILDKIT** / $TOTAL"
echo "- Squid proxy confirmed (✅): **$STAT_SQUID** / $TOTAL"
echo "- runs-on/cache confirmed (✅): **$STAT_RUNSON** / $TOTAL"
echo "- Confirmed NOT in use (❌): **$STAT_NO_CACHE** — need cache config"
echo "- No NPU runner jobs found: **$STAT_NO_NPU** — repos don't use our NPU runners"
echo "- Unknown / logs unavailable (-): **$STAT_ERROR**"
echo ""
echo "Audit complete."
