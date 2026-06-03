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

    while [ "$page" -le "$max_pages" ] && [ "$npu_found" = false ]; do
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

        # Strip GitHub Actions log annotations
        sed -i 's/##\[group\]//g; s/##\[endgroup\]//g; s/##\[error\]//g; s/##\[warning\]//g; s/##\[notice\]//g; s/##\[command\]//g' "$log_file" 2>/dev/null || true

        # ---------- Search for PyPI cache evidence (正面 + 反面) ----------
        ev_pypi=""
        counter_evidence_pypi=""
        # P1: "Looking in indexes" containing cache host → ✅
        grep_line=$(grep -m1 -i "Looking in indexes" "$log_file" 2>/dev/null | grep "$PYPI_CACHE_HOST" || true)
        if [ -n "$grep_line" ]; then
            repo_pypi=true
            ev_pypi="pip-index: ${grep_line:0:100}"
        fi

        if [ "$repo_pypi" = false ]; then
            grep_line=$(grep -m1 -E "PIP_INDEX_URL|PIP_EXTRA_INDEX_URL" "$log_file" 2>/dev/null | grep "$PYPI_CACHE_HOST" || true)
            if [ -n "$grep_line" ]; then
                repo_pypi=true
                ev_pypi="pip-env: ${grep_line:0:100}"
            fi
        fi

        if [ "$repo_pypi" = false ]; then
            grep_line=$(grep -m1 -iE "index-url|extra-index-url" "$log_file" 2>/dev/null | grep "$PYPI_CACHE_HOST" || true)
            if [ -n "$grep_line" ]; then
                repo_pypi=true
                ev_pypi="pip-config: ${grep_line:0:100}"
            fi
        fi

        if [ "$repo_pypi" = false ]; then
            grep_line=$(grep -m1 "$PYPI_CACHE_HOST" "$log_file" 2>/dev/null || true)
            if [ -n "$grep_line" ]; then
                repo_pypi=true
                ev_pypi="pip-broad: ${grep_line:0:100}"
            fi
        fi

        # Counter-evidence: pip index URL without cache host (proves NOT using cache)
        if [ "$repo_pypi" = false ]; then
            # Show what pip IS actually using
            grep_line=$(grep -m1 -i "Looking in indexes" "$log_file" 2>/dev/null || true)
            if [ -n "$grep_line" ]; then
                counter_evidence_pypi="pip uses: ${grep_line:0:120}"
            else
                # Fallback: show pip config output
                grep_line=$(grep -m1 -i "pip config" "$log_file" 2>/dev/null || true)
                if [ -n "$grep_line" ]; then
                    counter_evidence_pypi="pip config: ${grep_line:0:120}"
                fi
            fi
        fi

        # ---------- Search for APT cache evidence (正面 + 反面) ----------
        ev_apt=""
        counter_evidence_apt=""
        grep_line=$(grep -m1 -iE "^Get:|^Hit:|^Ign:" "$log_file" 2>/dev/null | grep -E "$APT_PATTERN" || true)
        if [ -n "$grep_line" ]; then
            repo_apt=true
            ev_apt="apt-get: ${grep_line:0:100}"
        fi

        if [ "$repo_apt" = false ]; then
            grep_line=$(grep -m1 -i "Acquire::http" "$log_file" 2>/dev/null | grep -E "$APT_PATTERN" || true)
            if [ -n "$grep_line" ]; then
                repo_apt=true
                ev_apt="apt-proxy: ${grep_line:0:100}"
            fi
        fi

        if [ "$repo_apt" = false ]; then
            grep_line=$(grep -m1 -iE "sed.*${APT_PATTERN}" "$log_file" 2>/dev/null || true)
            if [ -n "$grep_line" ]; then
                repo_apt=true
                ev_apt="apt-sed: ${grep_line:0:100}"
            fi
        fi

        if [ "$repo_apt" = false ]; then
            grep_line=$(grep -m1 -E "$APT_PATTERN" "$log_file" 2>/dev/null | grep -iE "apt|sources|mirror|repo" || true)
            if [ -n "$grep_line" ]; then
                repo_apt=true
                ev_apt="apt-broad: ${grep_line:0:100}"
            fi
        fi

        # Counter-evidence: apt source URL without cache (proves NOT using cache)
        if [ "$repo_apt" = false ]; then
            grep_line=$(grep -m1 -iE "^Get:|^Hit:" "$log_file" 2>/dev/null | grep -vE "$APT_PATTERN|$PYPI_CACHE_HOST" || true)
            if [ -n "$grep_line" ]; then
                counter_evidence_apt="apt source: ${grep_line:0:120}"
            else
                grep_line=$(grep -m1 -iE "apt-get install|apt-get update" "$log_file" 2>/dev/null || true)
                if [ -n "$grep_line" ]; then
                    counter_evidence_apt="apt cmd: ${grep_line:0:120}"
                fi
            fi
        fi

        rm -f "$log_file"

        # Got a usable log — record which job it came from
        repo_run="${c_run_branch}/${c_run_name}"
        repo_runner="$c_job_labels"
        log_ok=true
        break

    done <<< "$candidates"

    # ---------- Output ----------
    if [ "$log_ok" = false ]; then
        # Found NPU jobs but ALL logs expired/unavailable
        first_candidate=$(echo "$candidates" | grep -v '^$' | head -1)
        first_runner=$(echo "$first_candidate" | cut -d'|' -f6)
        echo "| $REPO | (NPU jobs found, logs expired) | $first_runner | ⚠️ | ⚠️ | NPU runner jobs found but all logs expired (>90 days) |"
        STAT_ERROR=$((STAT_ERROR + 1))
        continue
    fi

    pypi_mark="❌"
    apt_mark="❌"
    if [ "$repo_pypi" = true ]; then
        pypi_mark="✅"
        STAT_PYPI=$((STAT_PYPI + 1))
    fi
    if [ "$repo_apt" = true ]; then
        apt_mark="✅"
        STAT_APT=$((STAT_APT + 1))
    fi

    repo_evidence="${ev_pypi}; ${ev_apt}"
    repo_evidence="${repo_evidence# ; }"
    repo_evidence="${repo_evidence% ; }"

    # Build counter-evidence string (反面证据) for ❌ case
    counter_ev="${counter_evidence_pypi}; ${counter_evidence_apt}"
    counter_ev="${counter_ev# ; }"
    counter_ev="${counter_ev% ; }"

    if [ "$repo_pypi" = true ] || [ "$repo_apt" = true ]; then
        echo "| $REPO | $repo_run | $repo_runner | $pypi_mark | $apt_mark | ${repo_evidence:0:200} |"
    else
        echo "| $REPO | $repo_run | $repo_runner | ❌ | ❌ | 未用缓存: ${counter_ev:0:200} |"
        STAT_NO_CACHE=$((STAT_NO_CACHE + 1))
    fi

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