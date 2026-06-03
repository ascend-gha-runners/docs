#!/bin/bash
set -euo pipefail

# ==============================================================================
# CI 缓存审计脚本 — 基于 GitHub Actions 运行日志分析
#
# 策略：
#   1. 支持两种搜索模式：
#      - 自动模式：翻页搜索所有 run，找 NPU runner job，下载日志
#      - 定向模式：repos.txt 每行可指定 workflow 文件名，直接搜该 workflow
#   2. 找到 NPU job 后如果日志过期，继续翻找下一个可用日志的 job
#   3. Runner label 过滤跳过 ubuntu-latest 等无关 workflow
#
# repos.txt 格式：
#   org/repo                           — 自动模式，翻页搜所有 run
#   org/repo|workflow-file.yml         — 定向模式，只搜指定 workflow 的 run
#
# 环境变量：
#   RUNNER_FILTER    — runner label 过滤词（逗号分隔），默认 "linux-aarch64,self-hosted"
#   MAX_NPU_SEARCH   — 自动模式最多搜多少个 run，默认 100
#   PYPI_CACHE_HOST  — PyPI 缓存主机名
#   APT_CACHE_PORT   — APT 缓存端口
# ==============================================================================

if ! command -v jq &>/dev/null; then
    echo "Error: jq is not installed." >&2
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Error: gh (GitHub CLI) is not installed." >&2
    exit 1
fi

INPUT_FILE="$1"
if [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: $0 <repos_file>" >&2
    exit 1
fi

# ---------- Configuration ----------
PYPI_CACHE_HOST="${PYPI_CACHE_HOST:-cache-service.nginx-pypi-cache.svc.cluster.local}"
APT_CACHE_PORT="${APT_CACHE_PORT:-8081}"
APT_CACHE_HOST="${APT_CACHE_HOST:-}"
RUNNER_FILTER="${RUNNER_FILTER:-linux-aarch64,self-hosted}"
MAX_NPU_SEARCH="${MAX_NPU_SEARCH:-100}"
PER_PAGE="${PER_PAGE:-30}"

RUNNER_REGEX=$(echo "$RUNNER_FILTER" | sed 's/,/|/g')

if [ -n "$APT_CACHE_HOST" ]; then
    APT_PATTERN="${APT_CACHE_HOST}"
else
    APT_PATTERN=":${APT_CACHE_PORT}"
fi

LOG_DIR="/tmp/cache-audit-logs"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

echo "Log-based Cache Audit Configuration:"
echo " - PyPI Cache Host:  $PYPI_CACHE_HOST"
echo " - APT Pattern:      $APT_PATTERN"
echo " - Runner Filter:    $RUNNER_FILTER (regex: $RUNNER_REGEX)"
echo " - Max NPU Search:   $MAX_NPU_SEARCH runs"
echo "------------------------------------------------------------------"

STAT_PYPI=0
STAT_APT=0
STAT_NO_CACHE=0
STAT_NO_NPU=0
STAT_ERROR=0
TOTAL=0

echo "| 仓库 (Repository) | Run | Runner | PyPI 缓存 | APT 缓存 | 证据 (Evidence) |"
echo "| :--- | :--- | :--- | :---: | :---: | :--- |"

while IFS= read -r LINE || [ -n "$LINE" ]; do
    [[ -z "$LINE" || "$LINE" =~ ^[[:space:]]*# ]] && continue
    TOTAL=$((TOTAL + 1))

    # Parse repo and optional workflow filter
    # Format: org/repo   or   org/repo|workflow-file.yml
    REPO=$(echo "$LINE" | cut -d'|' -f1 | xargs)
    if [[ "$LINE" == *"|"* ]]; then
        WORKFLOW_FILTER=$(echo "$LINE" | cut -d'|' -f2 | xargs)
    else
        WORKFLOW_FILTER=""
    fi

    # ==================================================================
    # Phase 1: Collect candidate NPU jobs (paginate until found)
    # ==================================================================
    # Store candidates as: run_id|run_branch|run_name|job_id|job_name|job_labels
    candidates=""
    npu_found=false
    runs_scanned=0
    max_runs=${MAX_NPU_SEARCH}

    page=1
    max_pages=$(( (max_runs + PER_PAGE - 1) / PER_PAGE ))

    while [ "$page" -le "$max_pages" ]; do
        if [ -n "$WORKFLOW_FILTER" ]; then
            # Targeted: search only runs of the specified workflow
            runs_json=$(gh api "repos/$REPO/actions/workflows/${WORKFLOW_FILTER}/runs?per_page=$PER_PAGE&page=$page&status=completed" 2>/dev/null) || true
        else
            # Auto: search all completed runs
            runs_json=$(gh api "repos/$REPO/actions/runs?per_page=$PER_PAGE&page=$page&status=completed" 2>/dev/null) || true
        fi

        if [ -z "$runs_json" ]; then
            break
        fi

        run_count=$(echo "$runs_json" | jq -r '.workflow_runs | length' 2>/dev/null || echo "0")
        if [ "$run_count" = "0" ]; then
            break
        fi

        runs_scanned=$((runs_scanned + run_count))
        run_ids=$(echo "$runs_json" | jq -r '.workflow_runs[].id')

        for run_id in $run_ids; do
            run_branch=$(echo "$runs_json" | jq -r ".workflow_runs[] | select(.id == $run_id) | .head_branch")
            run_name=$(echo "$runs_json" | jq -r ".workflow_runs[] | select(.id == $run_id) | .name")

            jobs_json=$(gh api "repos/$REPO/actions/runs/$run_id/jobs" 2>/dev/null) || continue

            total_jobs=$(echo "$jobs_json" | jq -r '.total_count // 0')
            if [ "$total_jobs" = "0" ]; then
                continue
            fi

            filtered=$(echo "$jobs_json" | jq -r "
                .jobs[]
                | select(.labels | any(test(\"$RUNNER_REGEX\")))
                | [\"$run_id\", \"$run_branch\", \"$run_name\", .id, .name, (.labels | join(\",\"))] | join(\"|\")
            " 2>/dev/null) || true

            if [ -n "$filtered" ]; then
                candidates="$candidates"$'\n'"$filtered"
                npu_found=true
            fi
        done

        page=$((page + 1))
    done

    # ==================================================================
    # Phase 2: Try candidates one by one until a usable log is found
    # ==================================================================
    repo_pypi=false
    repo_apt=false
    repo_evidence=""
    repo_run=""
    repo_runner=""
    log_ok=false

    if [ "$npu_found" = false ]; then
        if [ "$runs_scanned" -gt 0 ]; then
            echo "| $REPO | (scanned $runs_scanned runs) | - | 🔍 | 🔍 | No NPU runner jobs found in last $runs_scanned runs |"
            STAT_NO_NPU=$((STAT_NO_NPU + 1))
        else
            echo "| $REPO | - | - | ⚠️ | ⚠️ | No completed runs / no access |"
            STAT_ERROR=$((STAT_ERROR + 1))
        fi
        continue
    fi

    # Deduplicate and sort candidates (newest run first = first found)
    candidates=$(echo "$candidates" | grep -v '^$' | sort -t'|' -k1 -rn | uniq)

    while IFS='|' read -r c_run_id c_run_branch c_run_name c_job_id c_job_name c_job_labels; do
        [ -z "$c_job_id" ] && continue

        log_file="$LOG_DIR/${REPO//\//_}_${c_run_id}_${c_job_id}.log"
        gh api "repos/$REPO/actions/jobs/$c_job_id/logs" >"$log_file" 2>/dev/null || {
            rm -f "$log_file"
            continue
        }

        if [ ! -s "$log_file" ]; then
            rm -f "$log_file"
            continue
        fi

        file_size=$(wc -c <"$log_file")
        if [ "$file_size" -lt 50 ]; then
            rm -f "$log_file"
            continue
        fi

        # Strip GitHub Actions log annotations, timestamps, and ANSI color codes
        sed -i 's/##\[group\]//g; s/##\[endgroup\]//g; s/##\[error\]//g; s/##\[warning\]//g; s/##\[notice\]//g; s/##\[command\]//g' "$log_file" 2>/dev/null || true
        sed -i 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\.[0-9]*Z //' "$log_file" 2>/dev/null || true
        sed -i 's/\x1b\[[0-9;]*m//g' "$log_file" 2>/dev/null || true

        # Pre-check: skip jobs with no package installation activity at all
        # (e.g. docs-check, lint-only jobs that use pre-built images)
        if ! grep -qiE "pip install|apt-get install|apt install|uv install|uv pip|dnf install|yum install|rustup toolchain|cargo install" "$log_file" 2>/dev/null; then
            rm -f "$log_file"
            continue
        fi

        # ---------- Search for PyPI cache evidence (正面 + 反面) ----------
        ev_pypi=""
        counter_evidence_pypi=""

        # 第一步：检查运行时实际使用的 index（最高优先级，能覆盖所有配置）
        # "Looking in indexes:" 是 pip 实际执行时打印的，反映真实行为
        actual_index_line=$(grep -m1 -i "Looking in indexes" "$log_file" 2>/dev/null || true)

        if [ -n "$actual_index_line" ]; then
            # 有运行时证据，直接用它判断，不再看配置文件
            if echo "$actual_index_line" | grep -q "$PYPI_CACHE_HOST"; then
                repo_pypi=true
                ev_pypi="pip实际用缓存: ${actual_index_line:0:200}"
            else
                # 运行时用的不是缓存地址，直接判 ❌，不管配置怎么写
                counter_evidence_pypi="实际用: ${actual_index_line:0:200}"
            fi
        else
            # 没有 "Looking in indexes:" 输出（uv 静默下载 / 未安装包）
            # 退回到配置层面判断，标记为弱证据(配置)

            # uv 尊重 pip config，检测 "pip config set global.index-url <cache>" 作为弱证据
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
                # 只有不含 "pip config set"（配置命令）时才算，避免误判执行配置操作为实际使用
                if [ -n "$grep_line" ] && ! echo "$grep_line" | grep -qi "pip config set"; then
                    repo_pypi=true
                    ev_pypi="pip-config(配置,无运行时证据): ${grep_line:0:200}"
                fi
            fi

            if [ "$repo_pypi" = false ]; then
                # 排除 apt/sed 相关行，避免把 apt 配置命令误判为 pip 证据
                grep_line=$(grep -m1 "$PYPI_CACHE_HOST" "$log_file" 2>/dev/null \
                    | grep -viE "apt|sed|sources\.list|Get:|Hit:|Ign:" || true)
                if [ -n "$grep_line" ]; then
                    repo_pypi=true
                    ev_pypi="pip-broad(配置): ${grep_line:0:200}"
                fi
            fi
        fi

        # ---------- Search for APT cache evidence (正面 + 反面) ----------
        ev_apt=""
        counter_evidence_apt=""
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

        # Counter-evidence: apt source URL without cache (proves NOT using cache)
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

        rm -f "$log_file"

        # Got a usable log — record which job it came from
        repo_run="${c_run_branch}/${c_run_name}"
        repo_runner="$c_job_labels"
        repo_job_url="https://github.com/${REPO}/actions/runs/${c_run_id}/job/${c_job_id}"
        log_ok=true
        break

    done <<< "$candidates"

    # ---------- Output ----------
    if [ "$log_ok" = false ]; then
        # Found NPU jobs but ALL logs expired/unavailable
        first_candidate=$(echo "$candidates" | grep -v '^$' | head -1)
        first_run_id=$(echo "$first_candidate" | cut -d'|' -f1)
        first_job_id=$(echo "$first_candidate" | cut -d'|' -f4)
        first_runner=$(echo "$first_candidate" | cut -d'|' -f6)
        first_url="https://github.com/${REPO}/actions/runs/${first_run_id}/job/${first_job_id}"
        echo "| $REPO | (NPU jobs found, logs expired) | $first_runner | ⚠️ | ⚠️ | NPU runner jobs found but all logs expired (>90 days) — [查看]($first_url) |"
        STAT_ERROR=$((STAT_ERROR + 1))
        continue
    fi

    job_link="[日志](${repo_job_url})"

    # 每个缓存类型独立判断，区分三种状态：
    #   ✅ 找到正面证据（确认使用了缓存）
    #   ❌ 找到反面证据（发现使用了其他地址，确认未使用缓存）
    #   ⚙️  无证据（日志中未出现相关输出，无法判断）

    if [ "$repo_pypi" = true ]; then
        pypi_mark="✅"
        pypi_detail="${ev_pypi}"
        STAT_PYPI=$((STAT_PYPI + 1))
    elif [ -n "$counter_evidence_pypi" ]; then
        pypi_mark="❌"
        pypi_detail="反面证据: ${counter_evidence_pypi}"
        STAT_NO_CACHE=$((STAT_NO_CACHE + 1))
    else
        pypi_mark="⚙️"
        pypi_detail="无证据(日志中未出现 pip index 相关输出)"
    fi

    if [ "$repo_apt" = true ]; then
        apt_mark="✅"
        apt_detail="${ev_apt}"
        STAT_APT=$((STAT_APT + 1))
    elif [ -n "$counter_evidence_apt" ]; then
        apt_mark="❌"
        apt_detail="反面证据: ${counter_evidence_apt}"
    else
        apt_mark="⚙️"
        apt_detail="无证据(日志中未出现 apt Get/Hit 相关输出)"
    fi

    evidence="${pypi_detail}; ${apt_detail}"
    evidence="${evidence# ; }"
    evidence="${evidence% ; }"

    echo "| $REPO | $repo_run | $repo_runner | $pypi_mark | $apt_mark | ${evidence:0:400} $job_link |"

    rm -f "$LOG_DIR/${REPO//\//_}"*.log

done < "$INPUT_FILE"

rm -rf "$LOG_DIR"

# ---------- Summary ----------
echo ""
echo "## Summary"
echo ""
echo "- Total repos checked: **$TOTAL**"
echo "- PyPI cache hit: **$STAT_PYPI** / $TOTAL"
echo "- APT cache hit: **$STAT_APT** / $TOTAL"
echo "- NPU job found but no cache (❌): **$STAT_NO_CACHE** — need cache config"
echo "- No NPU runner jobs found (🔍): **$STAT_NO_NPU** — repos don't use our NPU runners"
echo "- Logs expired / unavailable (⚠️): **$STAT_ERROR**"
echo ""
echo "Audit complete."