#!/bin/bash
# ==============================================================================
# 加速 CI 检查脚本 (Acceleration CI Check Script)
# 检查单个仓库的 workflow 文件是否配置了加速缓存。
#
# 用法:
#   bash check_acceleration.sh org/repo
#
# 环境变量:
#   GH_TOKEN        — GitHub API token（必须）
#   PYPI_CACHE_HOST — PyPI 缓存主机名（默认 cache-service.nginx-pypi-cache.svc.cluster.local）
#   APT_CACHE_PORT  — APT 缓存端口（默认 8081）
#
# 输出: Markdown 格式报告（stdout）
# ==============================================================================

set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
    echo "Usage: $0 org/repo" >&2
    exit 1
fi

# ---------- Configuration ----------
PYPI_CACHE_HOST="${PYPI_CACHE_HOST:-cache-service.nginx-pypi-cache.svc.cluster.local}"
APT_CACHE_PORT="${APT_CACHE_PORT:-8081}"

# ---------- Helpers ----------
check_dep() {
    if ! command -v "$1" &>/dev/null; then
        echo "Error: $1 is not installed." >&2
        exit 1
    fi
}
check_dep gh
check_dep jq

# ---------- Get default branch ----------
DEFAULT_BRANCH=$(gh api "repos/$REPO" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null || true)
if [ -z "$DEFAULT_BRANCH" ]; then
    echo "| $REPO | ⚠️ 无法获取仓库信息 | 仓库不存在或无访问权限 |"
    exit 0
fi

# ---------- Get workflow files ----------
WORKFLOW_FILES=$(gh api "repos/$REPO/contents/.github/workflows?ref=$DEFAULT_BRANCH" --jq '.[].name' 2>/dev/null || true)
if [ -z "$WORKFLOW_FILES" ]; then
    echo "| $REPO | ⚠️ 无 workflow 文件 | ${DEFAULT_BRANCH} 分支下没有 .github/workflows/ 目录 |"
    exit 0
fi

# ---------- Scan workflows ----------
HAS_PYPI=false
HAS_APT=false
HAS_RUST=false
HAS_YUM=false
HAS_CCACHE=false
HAS_UV=false

for FILE in $WORKFLOW_FILES; do
    [[ ! "$FILE" =~ \.(yml|yaml)$ ]] && continue

    CONTENT=$(gh api "repos/$REPO/contents/.github/workflows/$FILE?ref=$DEFAULT_BRANCH" \
        --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)
    [ -z "$CONTENT" ] && continue

    echo "$CONTENT" | grep -qF "$PYPI_CACHE_HOST" && HAS_PYPI=true
    echo "$CONTENT" | grep -qF ":$APT_CACHE_PORT" && HAS_APT=true
    echo "$CONTENT" | grep -q "RUSTUP_DIST_SERVER\|:8082" && HAS_RUST=true
    echo "$CONTENT" | grep -q ":8083.*openeuler\|openeuler.*:8083" && HAS_YUM=true
    echo "$CONTENT" | grep -q "ccache" && HAS_CCACHE=true
    echo "$CONTENT" | grep -qP "(^|\s)uv(\s|$)" && HAS_UV=true
done

# ---------- Output ----------
echo "| 加速类型 | 状态 | 检测说明 |"
echo "| --- | --- | --- |"
echo "| PyPI 缓存 | $($HAS_PYPI && echo '✅' || echo '❌') | workflow 中配置了 $PYPI_CACHE_HOST |"
echo "| APT 缓存  | $($HAS_APT && echo '✅' || echo '❌') | workflow 中配置了 :$APT_CACHE_PORT |"
echo "| Rust 缓存 | $($HAS_RUST && echo '✅' || echo '❌') | workflow 中配置了 RUSTUP_DIST_SERVER / :8082 |"
echo "| YUM 缓存  | $($HAS_YUM && echo '✅' || echo '❌') | workflow 中配置了 :8083 + openeuler |"
echo "| ccache    | $($HAS_CCACHE && echo '✅' || echo '❌') | workflow 中配置了 ccache |"
echo "| uv        | $($HAS_UV && echo '✅' || echo '❌') | workflow 中配置了 uv |"
echo ""
echo "> 检查仓库: \`$REPO\` · 分支: \`$DEFAULT_BRANCH\` · 参考: https://ascend-gha-runners.github.io/docs/feature/"
