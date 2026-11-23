#!/bin/bash
set -euo pipefail

# ==============================================================================
# CI 缓存审计脚本 — 基于 GitHub Actions 运行日志 + 部署仓库接线状态分析
#
# 缓存维度分两类（详见 docs/cache-audit-strategy-zh.md）：
#
#   A. 项目自配型（项目仓库可见，日志可验证）：
#      PyPI / APT / CCache / uv / runs-on cache —— 只扫 job 日志
#
#   B. 基建注入型（由 ascend-ci-deployment 的 pod template 注入，项目仓库
#      workflow 与日志中基本不可见，不能扫项目仓库来判定）：
#      BuildKit —— postStart: buildkit-acquire + docker buildx create
#                  --driver remote --use，共享 buildkitd 的 PVC 层缓存
#                  服务端自动生效，项目无需 cache-from/cache-to
#      Squid    —— runner/job pod env 注入 HTTP_PROXY（透明代理）
#      git-cdn  —— postStart git config url.insteadOf（透明改写）
#      B 类以部署仓库接线状态为权威判定（DEPLOY_REPO_DIR 本地克隆 +
#      grep），job 日志运行时证据为补充。
#
# 优化策略（v5）：
#   1. REST 获取 runs（success+failure）
#   2. 候选收集：从 runs 中收集最多 MAX_CANDIDATES 个 NPU job 候选
#   3. 聚合证据：Phase 2 扫描多个候选日志，对每种缓存类型取"任一日志有正面证据→✅"
#   4. 并发：repo 级 PARALLEL 并发处理
#   5. 全量扫描：设 MAX_NPU_SEARCH=0 触发全量模式（内部 cap 200 runs + 30 candidates
#      + unlimited log aggregation），避免 API rate limit (5000/hr) 耗尽导致静默失败
#   6. 基建注入型维度：部署仓库本地克隆 grep（0 API 调用，权威），
#      日志仅提供运行时补充证据（buildkitd remote driver / CACHED /
#      Runner is running behind proxy 等）
#
# 标记图例：
#   ✅ = confirmed in use（部署侧已接线 或 日志/工作流中找到使用证据）
#   ❌ = confirmed NOT in use（部署侧未接线 或 有反面证据且无正面证据）
#   -  = unknown（无证据或无法确定）
#
# 检测维度（8 列）：
#   PyPI / APT / CCache / uv —— 基于 job 日志
#   BuildKit / Squid / git-cdn —— 部署仓库接线（权威）+ job 日志（运行时）
#   runs-on/cache —— runs-on 的 S3 后端 Actions 缓存（runs-on/cache@v5），
#                    项目侧可见，workflow 静态扫 + 日志
#
# repos.txt 格式：
#   org/repo                           — 自动模式
#   org/repo|workflow-file.yml         — 定向模式，REST 翻页搜指定 workflow
#   可选默认值列（第 3 列起）：pypi|apt|ccache|uv|buildkit|squid|gitcdn|runson
#
# 环境变量（设 0 = 全量模式，内部使用 cap 防止 rate limit）：
#   DEPLOY_REPO_DIR   — ascend-ci-deployment 本地克隆路径（基建注入型维度的
#                       权威数据源；未设置/不存在时 B 类维度降级为仅日志判定）
#   RUNNER_FILTER     — runner label 过滤词（逗号分隔），默认 "linux-aarch64,linux-amd64"
#   MAX_NPU_SEARCH    — 最多搜多少个 run，默认 50；0 = 全量模式（cap 200）
#   MAX_CANDIDATES    — Phase 1 最多收集多少个候选 job，默认 15；0 = 全量模式（cap 30）
#   MAX_LOGS_TO_CHECK — Phase 2 最多下载多少个候选日志做聚合，默认 10；0 = 无上限（全量聚合）
#   PARALLEL          — 并发 repo 数，默认 4
#   AUDIT_TOKENS      — 逗号分隔的 token 列表，按 repo 轮询分散 API 限额（默认用 GH_TOKEN）
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
# 部署仓库本地克隆（基建注入型维度的权威数据源；见头部注释 B 类说明）
DEPLOY_REPO_DIR="${DEPLOY_REPO_DIR:-}"
# Squid 运行时证据：只认我们集群的 squid 服务地址（runner 会打印
# "Runner is running behind proxy server 'http://squid-cache.squid.svc...'"）。
# 不匹配裸 :3128 / HTTP_PROXY —— 项目自配的其它代理（如 100.68.174.87:3128）
# 不是我们的缓存，匹配了只会造成假阳性。
SQUID_LOG_PATTERN='squid-cache\.squid\.svc\.cluster\.local'
# BuildKit 运行时正面证据：
#   remote driver —— buildx 每次构建开头都会打印 building with "buildkitd"
#                    instance using remote driver（我们的 postStart 创建的
#                    builder 名固定叫 buildkitd，本地 dind/默认 builder 打印
#                    "default" + docker driver，可区分）
#   缓存命中      —— #N CACHED（plain progress，GHA 无 TTY 的默认格式）、
#                    => CACHED / CACHED [（tty/auto 格式）、importing/exporting cache
#   buildkit 进度 —— #N [internal] load ... / #N [x/y] RUN ...（仅说明走了 buildkit）
BUILDKIT_REMOTE_PATTERN='building with "?buildkitd"? instance|buildkit-acquire|buildkitd-dispatcher|--builder buildkitd|\.buildkitd:1234'
BUILDKIT_CACHE_PATTERN='#[0-9]+ CACHED|=> CACHED|CACHED \[[0-9]|importing cache manifest|exporting cache|exporting layers'
BUILDKIT_PROGRESS_PATTERN='#[0-9]+ \[internal\] load (build definition|metadata)|#[0-9]+ \[[0-9]+/[0-9]+\] '
# BuildKit 反面证据：legacy builder 输出（Step N/M，未走 BuildKit）、
# 无 daemon / 无 docker（非接线 runner 上构建根本无法发生）
BUILDKIT_COUNTER_PATTERN='Step [0-9]+/[0-9]+ :|Cannot connect to the Docker daemon|docker: command not found'
# git-cdn 运行时证据：透明改写只在 git 报错/verbose 时露出真实 URL
GITCDN_LOG_PATTERN='git-cdn-service\.git-cdn'
RUNNER_FILTER="${RUNNER_FILTER:-linux-aarch64,linux-amd64}"
MAX_NPU_SEARCH="${MAX_NPU_SEARCH:-50}"
MAX_CANDIDATES="${MAX_CANDIDATES:-15}"
MAX_LOGS_TO_CHECK="${MAX_LOGS_TO_CHECK:-10}"
PARALLEL="${PARALLEL:-4}"
PER_PAGE="${PER_PAGE:-30}"

# Audit token pool: comma-separated tokens, rotated per repo so API usage is
# spread across multiple rate-limit buckets. Falls back to GH_TOKEN.
AUDIT_TOKEN_LIST=()
if [ -n "${AUDIT_TOKENS:-}" ]; then
    IFS=',' read -r -a _audit_raw <<< "$AUDIT_TOKENS"
    for _t in "${_audit_raw[@]}"; do
        if [ -n "$_t" ]; then
            AUDIT_TOKEN_LIST+=("$_t")
        fi
    done
fi
if [ ${#AUDIT_TOKEN_LIST[@]} -eq 0 ]; then
    AUDIT_TOKEN_LIST=("${GH_TOKEN:-}")
fi

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

echo "Log-based Cache Audit Configuration (v5 — logs + deployment wiring):"
echo " - PyPI Cache Host:  $PYPI_CACHE_HOST"
echo " - APT Pattern:      $APT_PATTERN"
echo " - CCache Keyword:   $CCACHE_KEYWORD"
echo " - Runner Filter:    $RUNNER_FILTER (regex: $RUNNER_REGEX)"
if [ -n "$DEPLOY_REPO_DIR" ] && [ -d "$DEPLOY_REPO_DIR" ]; then
echo " - Deploy Repo Dir:  $DEPLOY_REPO_DIR (BuildKit/Squid/git-cdn 以部署侧接线为准)"
else
echo " - Deploy Repo Dir:  NOT SET (BuildKit/Squid/git-cdn 降级为仅日志判定)"
fi
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
# Infra-side wiring scan (B 类维度的权威判定)
#
# BuildKit / Squid / git-cdn 由 ascend-ci-deployment 的 pod template 注入：
#   BuildKit: postStart 执行 buildkit-acquire + docker buildx create
#             --driver remote --use（共享 buildkitd 的缓存自动生效）
#   Squid:    runner/job pod env 注入 HTTP_PROXY（透明代理）
#   git-cdn:  postStart git config url.insteadOf（透明改写）
# 这些接线对项目仓库的 workflow 完全不可见，因此不能扫项目仓库判定，
# 必须读部署仓库本身。DEPLOY_REPO_DIR 指向部署仓库的本地克隆（0 API 调用）。
#
# repo -> 部署仓库项目根目录的映射以 values.yaml 的 githubConfigUrl 为准
# （目录名可能是旧 org 名，如 volcengine/verl 实为 verl-project/verl）。
#
# Sets globals: infra_found ("found" | "notfound" | "unknown")
#               infra_wired_buildkit infra_ev_buildkit
#               infra_wired_squid    infra_ev_squid
#               infra_wired_gitcdn   infra_ev_gitcdn
# ==============================================================================
scan_deployment_wiring() {
    local REPO="$1"
    infra_found="unknown"
    infra_wired_buildkit=false
    infra_wired_squid=false
    infra_wired_gitcdn=false
    infra_ev_buildkit=""
    infra_ev_squid=""
    infra_ev_gitcdn=""

    if [ -z "$DEPLOY_REPO_DIR" ] || [ ! -d "$DEPLOY_REPO_DIR" ]; then
        return 0
    fi

    # githubConfigUrl -> 项目根目录（values.yaml 在
    # projects/{org}/{repo}/{scale-set}/values.yaml，dirname 两次回到根）
    local repo_esc roots line
    repo_esc=$(printf '%s' "$REPO" | sed 's/[.[\*^$()+?{}|]/\\&/g')
    roots=$(grep -rlE --include='values.yaml' --exclude-dir=.git \
        "github\.com/${repo_esc}([^a-zA-Z0-9_.-]|$)" \
        "$DEPLOY_REPO_DIR/projects" "$DEPLOY_REPO_DIR/other" 2>/dev/null \
        | xargs -r -n1 dirname | xargs -r -n1 dirname | sort -u) || true

    if [ -z "$roots" ]; then
        infra_found="notfound"
        return 0
    fi
    infra_found="found"

    if [ "$infra_wired_buildkit" = false ]; then
        line=$(grep -rm1 -E --include='*.yaml' --include='*.yml' --exclude-dir=.git \
            'buildkit-acquire|docker buildx create|BUILDKITD_ADDR' $roots 2>/dev/null) || true
        if [ -n "$line" ]; then
            infra_wired_buildkit=true
            line="${line#$DEPLOY_REPO_DIR/}"
            infra_ev_buildkit="部署侧已接线: ${line:0:160}"
        fi
    fi
    if [ "$infra_wired_squid" = false ]; then
        line=$(grep -rm1 -E --include='*.yaml' --include='*.yml' --exclude-dir=.git \
            'squid-cache\.squid\.svc\.cluster\.local|squid-ca-cert' $roots 2>/dev/null) || true
        if [ -n "$line" ]; then
            infra_wired_squid=true
            line="${line#$DEPLOY_REPO_DIR/}"
            infra_ev_squid="部署侧已接线(env透明注入): ${line:0:160}"
        fi
    fi
    if [ "$infra_wired_gitcdn" = false ]; then
        line=$(grep -rm1 -E --include='*.yaml' --include='*.yml' --exclude-dir=.git \
            'git-cdn-service' $roots 2>/dev/null) || true
        if [ -n "$line" ]; then
            infra_wired_gitcdn=true
            line="${line#$DEPLOY_REPO_DIR/}"
            infra_ev_gitcdn="部署侧已接线(insteadOf透明改写): ${line:0:160}"
        fi
    fi
    return 0
}

# ==============================================================================
# Static scan: read a repo's workflow YAML files for config-visible cache usage
# 仅保留项目侧可见的维度（runs-on/cache）。BuildKit/Squid/git-cdn 属基建注入型，
# 项目 workflow 中不存在，已改由 scan_deployment_wiring 判定。
# Sets globals: static_runson static_ev_runson
# ==============================================================================
scan_workflows_static() {
    local REPO="$1"
    static_runson=false
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
    done <<< "$files"
    return 0
}

# ==============================================================================
# Phase 2: search ONE log for cache evidence
# Sets globals: repo_pypi repo_apt repo_ccache repo_uv repo_buildkit repo_squid repo_gitcdn repo_runson
#               ev_pypi ev_apt ev_ccache ev_uv ev_buildkit ev_squid ev_gitcdn ev_runson
#               counter_evidence_pypi counter_evidence_apt
#               counter_evidence_ccache counter_evidence_uv
#               counter_evidence_buildkit counter_evidence_gitcdn counter_evidence_runson
#               repo_buildkit_level ("remote" | "cache" | "progress" | "")
# Returns: 0 = log has package activity (evidence searched)
#          1 = log has no package activity (skip)
# ==============================================================================
search_log_evidence() {
    local log_file="$1"

    # Pre-check: skip jobs with no package installation / cache activity
    if ! grep -qiE "pip install|apt-get install|apt install|uv install|uv pip|dnf install|yum install|rustup toolchain|cargo install|ccache|cmake|gcc|g\+\+|make|ninja|buildctl|build-push|cache-from|cache-to|import-cache|export-cache|buildcache|buildkit|docker build|docker buildx|CACHED|$SQUID_LOG_PATTERN|$GITCDN_LOG_PATTERN|runs-on/cache|Cache restored|Cache saved" "$log_file" 2>/dev/null; then
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
    # 基建注入型：共享 buildkitd 的层缓存由服务端 PVC 自动生效，项目无需
    # cache-from/cache-to，因此不以缓存指令为证据，而是看构建是否真的走了
    # 我们 postStart 创建的远程 builder（名为 buildkitd）以及缓存是否命中。
    # 注意 plain progress 格式（GHA 无 TTY 默认）：命中行是 "#5 CACHED"，
    # 没有旧脚本匹配的 "=> CACHED" 或 "CACHED ["（那是 tty/auto 格式）。
    ev_buildkit=""
    counter_evidence_buildkit=""
    repo_buildkit=false
    repo_buildkit_level=""

    # Level 1 (strongest): 远程 builder 实锤 —— buildx 构建开头打印
    # "#0 building with \"buildkitd\" instance using remote driver"
    grep_line=$(grep -m1 -E "$BUILDKIT_REMOTE_PATTERN" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_buildkit=true
        repo_buildkit_level="remote"
        ev_buildkit="buildkit-远程builder(运行时): ${grep_line:0:200}"
    fi
    # Level 2: 缓存命中/导出（importing/exporting cache、#N CACHED、=> CACHED）
    if [ "$repo_buildkit" = false ]; then
        grep_line=$(grep -m1 -E "$BUILDKIT_CACHE_PATTERN" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            repo_buildkit=true
            repo_buildkit_level="cache"
            ev_buildkit="buildkit缓存命中(运行时): ${grep_line:0:200}"
        fi
    fi
    # Level 3 (weakest): buildkit 进度格式（仅说明走了 BuildKit，
    # 无法区分我们的远程 builder 与本地 dind）
    if [ "$repo_buildkit" = false ]; then
        grep_line=$(grep -m1 -E "$BUILDKIT_PROGRESS_PATTERN" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            repo_buildkit=true
            repo_buildkit_level="progress"
            ev_buildkit="buildkit构建进度(运行时): ${grep_line:0:200}"
        fi
    fi
    # Counter-evidence: 构建未走共享 buildkitd —— legacy builder 输出
    # （Step N/M）、无 docker daemon / 无 docker 命令（未接线 runner）
    if [ "$repo_buildkit" = false ]; then
        grep_line=$(grep -m1 -E "$BUILDKIT_COUNTER_PATTERN" "$log_file" 2>/dev/null || true)
        if [ -n "$grep_line" ]; then
            counter_evidence_buildkit="构建未走buildkit: ${grep_line:0:200}"
        fi
    fi

    # ---------- Squid proxy evidence ----------
    # 基建注入型：HTTP_PROXY 在 pod 层注入，日志中可靠信号是 runner 打印的
    # "Runner is running behind proxy server 'http://squid-cache.squid.svc...'"。
    # 只匹配我们的 squid 服务地址，避免把项目自配代理（如 100.68.174.87:3128）
    # 误判为我们的缓存（旧脚本的真实假阳性案例：verl-project/uni-agent）。
    ev_squid=""
    counter_evidence_squid=""
    repo_squid=false

    grep_line=$(grep -m1 -iE "$SQUID_LOG_PATTERN" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_squid=true
        ev_squid="squid代理(运行时): ${grep_line:0:200}"
    fi

    # ---------- git-cdn evidence ----------
    # 基建注入型：postStart 的 git url.insteadOf 透明改写，仅在 git
    # 报错/verbose 输出中露出真实 URL（git-cdn-service.git-cdn...）
    ev_gitcdn=""
    counter_evidence_gitcdn=""
    repo_gitcdn=false

    grep_line=$(grep -m1 -iE "$GITCDN_LOG_PATTERN" "$log_file" 2>/dev/null || true)
    if [ -n "$grep_line" ]; then
        repo_gitcdn=true
        ev_gitcdn="git-cdn(运行时): ${grep_line:0:200}"
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
    local s_pypi=0 s_apt=0 s_ccache=0 s_uv=0 s_buildkit=0 s_squid=0 s_gitcdn=0 s_runson=0
    local s_no_cache=0 s_no_npu=0 s_error=0

    # Static scan of workflow files (project-side config-visible evidence: runs-on/cache)
    scan_workflows_static "$REPO" || true

    # Infra-side wiring scan (deployment repo clone; authoritative for
    # BuildKit / Squid / git-cdn — see header comment B 类说明)
    scan_deployment_wiring "$REPO" || true

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
            row="| $REPO | (scanned $runs_scanned runs) | - | - | - | - | - | - | - | - | - | No NPU runner jobs found in last $runs_scanned runs |"
            s_no_npu=1
        else
            row="| $REPO | - | - | - | - | - | - | - | - | - | - | No completed runs / no access |"
            s_error=1
        fi
        echo "$row" > "$row_file"
        echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_buildkit|$s_squid|$s_gitcdn|$s_runson|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"
        rm -rf "$log_dir"
        return 0
    fi

    # ===== Phase 2: Aggregate evidence from multiple candidate logs =====
    # For each cache type:
    #   ✅ = ANY log has positive evidence
    #   ❌ = NO log has positive evidence AND ANY log has counter-evidence
    #   -  = otherwise (no evidence in any direction)
    # B 类维度（buildkit/squid/git-cdn）另有部署侧接线状态兜底（见输出判定）。
    local agg_pypi=false agg_apt=false agg_ccache=false agg_uv=false
    local agg_buildkit=false agg_squid=false agg_gitcdn=false agg_runson=false
    local agg_ev_pypi="" agg_ev_apt="" agg_ev_ccache="" agg_ev_uv=""
    local agg_ev_buildkit="" agg_ev_squid="" agg_ev_gitcdn="" agg_ev_runson=""
    local agg_counter_pypi="" agg_counter_apt="" agg_counter_ccache="" agg_counter_uv=""
    local agg_counter_buildkit="" agg_counter_squid="" agg_counter_gitcdn="" agg_counter_runson=""
    local agg_buildkit_level=""
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
        curl -fsSL -H "Authorization: Bearer ${GH_TOKEN:-}" \
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
            agg_buildkit_level="$repo_buildkit_level"
        fi
        # Upgrade buildkit evidence level if a later log has stronger proof
        # (remote builder beats cache-hit beats progress format)
        if [ "$repo_buildkit" = true ] && [ "$repo_buildkit_level" = "remote" ] \
           && [ "$agg_buildkit_level" != "remote" ]; then
            agg_buildkit_level="remote"
            agg_ev_buildkit="$ev_buildkit"
        fi
        if [ "$repo_squid" = true ] && [ "$agg_squid" = false ]; then
            agg_squid=true
            agg_ev_squid="$ev_squid"
        fi
        if [ "$repo_gitcdn" = true ] && [ "$agg_gitcdn" = false ]; then
            agg_gitcdn=true
            agg_ev_gitcdn="$ev_gitcdn"
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
        if [ "$repo_gitcdn" = false ] && [ -n "$counter_evidence_gitcdn" ] && [ -z "$agg_counter_gitcdn" ]; then
            agg_counter_gitcdn="$counter_evidence_gitcdn"
        fi
        if [ "$repo_runson" = false ] && [ -n "$counter_evidence_runson" ] && [ -z "$agg_counter_runson" ]; then
            agg_counter_runson="$counter_evidence_runson"
        fi

        # Early exit: all 8 cache types have positive evidence, no need to check more logs
        if [ "$agg_pypi" = true ] && [ "$agg_apt" = true ] && [ "$agg_ccache" = true ] && [ "$agg_uv" = true ] \
           && [ "$agg_buildkit" = true ] && [ "$agg_squid" = true ] && [ "$agg_gitcdn" = true ] && [ "$agg_runson" = true ]; then
            break
        fi

    done <<< "$sorted_candidates"

    # ===== Output =====
    local row=""
    if [ "$logs_checked" -eq 0 ]; then
        # No usable logs found (download failed/empty or no package activity).
        # B 类维度仍可依据部署侧接线状态判定（基建注入型不依赖项目日志），
        # runs-on/cache 依据 workflow 静态扫描。
        local first_candidate first_run_id first_job_id first_runner first_url
        first_candidate=$(echo "$sorted_candidates" | grep -v '^$' | head -1)
        first_run_id=$(echo "$first_candidate" | cut -d'|' -f1)
        first_job_id=$(echo "$first_candidate" | cut -d'|' -f4)
        first_runner=$(echo "$first_candidate" | cut -d'|' -f6)
        first_url="https://github.com/${REPO}/actions/runs/${first_run_id}/job/${first_job_id}"
        local nb_mark ns_mark ng_mark nr_mark nb_ev="" ns_ev="" ng_ev="" nr_ev=""
        nb_mark="-"; ns_mark="-"; ng_mark="-"; nr_mark="-"
        if [ "$infra_wired_buildkit" = true ]; then nb_mark="✅"; nb_ev="$infra_ev_buildkit"; s_buildkit=1
        elif [ "$infra_found" = "found" ]; then nb_mark="❌"; nb_ev="部署侧未接线"
        elif [ "$infra_found" = "notfound" ]; then nb_ev="未在部署仓库找到该项目"
        else nb_ev="部署仓库不可用"; fi
        if [ "$infra_wired_squid" = true ]; then ns_mark="✅"; ns_ev="$infra_ev_squid"; s_squid=1
        elif [ "$infra_found" = "found" ]; then ns_mark="❌"; ns_ev="部署侧未接线"
        elif [ "$infra_found" = "notfound" ]; then ns_ev="未在部署仓库找到该项目"
        else ns_ev="部署仓库不可用"; fi
        if [ "$infra_wired_gitcdn" = true ]; then ng_mark="✅"; ng_ev="$infra_ev_gitcdn"; s_gitcdn=1
        elif [ "$infra_found" = "found" ]; then ng_mark="❌"; ng_ev="部署侧未接线"
        elif [ "$infra_found" = "notfound" ]; then ng_ev="未在部署仓库找到该项目"
        else ng_ev="部署仓库不可用"; fi
        if [ "$static_runson" = true ]; then nr_mark="✅"; nr_ev="$static_ev_runson"; s_runson=1; fi
        if [ "$log_no_pkg_activity" = 1 ]; then
            row="| $REPO | (NPU jobs found, no pkg activity) | $first_runner | - | - | - | - | $nb_mark | $ns_mark | $ng_mark | $nr_mark | NPU runner jobs found but no package installation in recent logs; ${nb_ev}; ${ns_ev}; ${ng_ev} — [查看]($first_url) |"
        else
            row="| $REPO | (NPU jobs found, log download failed) | $first_runner | - | - | - | - | $nb_mark | $ns_mark | $ng_mark | $nr_mark | NPU runner jobs found but logs could not be downloaded (expired or fetch failed); ${nb_ev}; ${ns_ev}; ${ng_ev} — [查看]($first_url) |"
        fi
        s_error=1
        echo "$row" > "$row_file"
        echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_buildkit|$s_squid|$s_gitcdn|$s_runson|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"
        rm -rf "$log_dir"
        return 0
    fi

    local job_link="[日志](${repo_job_url})"

    # Determine marks based on aggregated evidence
    local pypi_mark pypi_detail apt_mark apt_detail ccache_mark ccache_detail uv_mark uv_detail
    local buildkit_mark buildkit_detail squid_mark squid_detail gitcdn_mark gitcdn_detail runson_mark runson_detail

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

    # BuildKit（基建注入型）：运行时证据优先，其次部署侧接线，再反面证据
    if [ "$agg_buildkit" = true ]; then
        buildkit_mark="✅"; buildkit_detail="$agg_ev_buildkit"; s_buildkit=1
        # 运行时只有弱证据（进度格式）时，用部署侧接线补强结论
        if [ "$agg_buildkit_level" != "remote" ] && [ "$infra_wired_buildkit" = true ]; then
            buildkit_detail="${agg_ev_buildkit}; ${infra_ev_buildkit}"
        elif [ "$agg_buildkit_level" != "remote" ] && [ "$infra_found" = "found" ]; then
            buildkit_detail="${agg_ev_buildkit}; 部署侧未接线(疑似本地/外部构建)"
        fi
    elif [ "$infra_wired_buildkit" = true ]; then
        buildkit_mark="✅"
        buildkit_detail="$infra_ev_buildkit; 近期日志未见构建活动(接线即生效,任何 docker build 都会走共享 buildkitd)"
        s_buildkit=1
    elif [ -n "$agg_counter_buildkit" ]; then
        buildkit_mark="❌"; buildkit_detail="反面证据: ${agg_counter_buildkit}"; s_no_cache=1
    elif [ "$infra_found" = "found" ]; then
        buildkit_mark="❌"; buildkit_detail="部署侧未接线: 该项目 runner 无 buildkit 远程 builder 接线"; s_no_cache=1
    elif [ "$infra_found" = "notfound" ]; then
        buildkit_mark="-"; buildkit_detail="未在部署仓库找到该项目, 无法判定接线"
    else
        buildkit_mark="-"; buildkit_detail="部署仓库不可用, 仅日志未发现 buildkit 构建证据"
    fi

    # Squid（基建注入型）：运行时证据优先，其次部署侧接线
    if [ "$agg_squid" = true ]; then
        squid_mark="✅"; squid_detail="$agg_ev_squid"; s_squid=1
    elif [ "$infra_wired_squid" = true ]; then
        squid_mark="✅"
        squid_detail="$infra_ev_squid; 代理对 runner/job 透明, 日志仅偶尔可见"
        s_squid=1
    elif [ "$infra_found" = "found" ]; then
        squid_mark="❌"; squid_detail="部署侧未接线: 该项目 runner 未注入 squid 代理 env"; s_no_cache=1
    elif [ "$infra_found" = "notfound" ]; then
        squid_mark="-"; squid_detail="未在部署仓库找到该项目, 无法判定接线"
    else
        squid_mark="-"; squid_detail="部署仓库不可用, 仅日志未发现 squid 证据"
    fi

    # git-cdn（基建注入型）：运行时证据优先，其次部署侧接线
    if [ "$agg_gitcdn" = true ]; then
        gitcdn_mark="✅"; gitcdn_detail="$agg_ev_gitcdn"; s_gitcdn=1
    elif [ "$infra_wired_gitcdn" = true ]; then
        gitcdn_mark="✅"
        gitcdn_detail="$infra_ev_gitcdn; url 改写对 git 透明, 日志仅报错时可见"
        s_gitcdn=1
    elif [ "$infra_found" = "found" ]; then
        gitcdn_mark="❌"; gitcdn_detail="部署侧未接线: 该项目 runner 未配置 git-cdn insteadOf"; s_no_cache=1
    elif [ "$infra_found" = "notfound" ]; then
        gitcdn_mark="-"; gitcdn_detail="未在部署仓库找到该项目, 无法判定接线"
    else
        gitcdn_mark="-"; gitcdn_detail="部署仓库不可用, 仅日志未发现 git-cdn 证据"
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

    local evidence="${pypi_detail}; ${apt_detail}; ${ccache_detail}; ${uv_detail}; ${buildkit_detail}; ${squid_detail}; ${gitcdn_detail}; ${runson_detail}"
    evidence="${evidence# ; }"
    evidence="${evidence% ; }"
    # Sanitize: replace pipe chars to prevent markdown table column corruption
    evidence="${evidence//|/¦}"

    row="| $REPO | $repo_run | $repo_runner | $pypi_mark | $apt_mark | $ccache_mark | $uv_mark | $buildkit_mark | $squid_mark | $gitcdn_mark | $runson_mark | ${evidence:0:400} $job_link |"
    echo "$row" > "$row_file"
    echo "$s_pypi|$s_apt|$s_ccache|$s_uv|$s_buildkit|$s_squid|$s_gitcdn|$s_runson|$s_no_cache|$s_no_npu|$s_error" > "$stat_file"

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

echo "Processing $TOTAL repos with $PARALLEL parallel workers, ${#AUDIT_TOKEN_LIST[@]} audit token(s)..."
echo ""

# Output table header
echo "| 仓库 (Repository) | Run | Runner | PyPI 缓存 | APT 缓存 | CCache | uv | BuildKit | Squid | git-cdn | runs-on/cache | 证据 (Evidence) |"
echo "| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |"

# Process repos in parallel
# Use background processes with a concurrency limit
declare -a PIDS=()
_tok_idx=0
for line in "${REPO_LINES[@]}"; do
    # Rotate tokens per repo; each background subshell gets its own GH_TOKEN
    _tok="${AUDIT_TOKEN_LIST[$(( _tok_idx % ${#AUDIT_TOKEN_LIST[@]} ))]}"
    ( if [ -n "$_tok" ]; then export GH_TOKEN="$_tok"; fi; process_repo "$line" "$TMPDIR" ) &
    PIDS+=($!)
    _tok_idx=$((_tok_idx + 1))

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
STAT_GITCDN=0
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
        echo "| $REPO | - | - | - | - | - | - | - | - | - | - | Processing error — no output |"
        echo "0|0|0|0|0|0|0|0|0|0|1" > "$stat_file"
    fi

    if [ -f "$stat_file" ]; then
        IFS='|' read -r sp sa sc su sbk ssq sgc srs sn snn se < "$stat_file"
        STAT_PYPI=$((STAT_PYPI + sp))
        STAT_APT=$((STAT_APT + sa))
        STAT_CCACHE=$((STAT_CCACHE + sc))
        STAT_UV=$((STAT_UV + su))
        STAT_BUILDKIT=$((STAT_BUILDKIT + sbk))
        STAT_SQUID=$((STAT_SQUID + ssq))
        STAT_GITCDN=$((STAT_GITCDN + sgc))
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
echo "- git-cdn confirmed (✅): **$STAT_GITCDN** / $TOTAL"
echo "- runs-on/cache confirmed (✅): **$STAT_RUNSON** / $TOTAL"
echo "- Confirmed NOT in use (❌): **$STAT_NO_CACHE** — need cache config"
echo "- No NPU runner jobs found: **$STAT_NO_NPU** — repos don't use our NPU runners"
echo "- Unknown / logs unavailable (-): **$STAT_ERROR**"
echo ""
echo "Audit complete."
