#!/bin/bash

# ==============================================================================
# CI 缓存审计脚本 (CI Cache Audit Script)
# 用于检查多个仓库的 GitHub Workflows 是否配置了指定的 PyPI 和 APT 缓存。
# ==============================================================================

# 检查依赖 (Check Dependencies)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed."
    exit 1
fi

INPUT_FILE="$1"
if [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: $0 <repos_file>"
    echo "Example: $0 repos.txt"
    exit 1
fi

# ------------------------------------------------------------------------------
# 配置 (Configuration)
# ------------------------------------------------------------------------------
# PyPI 匹配关键词 (默认为内网缓存服务地址)
PYPI_KEYWORD="${PYPI_CACHE_KEYWORD:-cache-service.nginx-pypi-cache.svc.cluster.local}"

# APT 匹配模式 (匹配端口号或关键字)
APT_PATTERN="${APT_CACHE_PATTERN:-:8081|apt.*cache-service}"

# 打印运行参数 (Print Runtime Parameters)
echo "Audit Configuration:"
echo " - PyPI Keyword: $PYPI_KEYWORD"
echo " - APT Pattern:  $APT_PATTERN"
echo "------------------------------------------------------------------"

echo "| 仓库 (Repository) | 分支 (Branch) | 文件 (File) | PyPI 缓存 | APT 缓存 |"
echo "| :--- | :--- | :--- | :---: | :---: |"

while read -r REPO_FULL; do
    [ -z "$REPO_FULL" ] && continue
    [[ "$REPO_FULL" =~ ^# ]] && continue

    # 获取默认分支 (Get Default Branch)
    default_branch=$(gh api "repos/$REPO_FULL" --jq '.default_branch' 2>/dev/null)
    if [ -z "$default_branch" ]; then
        echo "| $REPO_FULL | - | - | ⚠️ Repo Not Found/Empty | - |"
        continue
    fi

    # 获取所有分支并优先主分支 (Get All Branches, Prioritize Default)
    all_branches=$(gh api "repos/$REPO_FULL/branches" --jq '.[].name' 2>/dev/null)
    sorted_branches=$(echo -e "$default_branch\n$all_branches" | awk '!seen[$0]++')

    repo_done=false
    repo_printed=false

    for branch in $sorted_branches; do
        # 获取工作流文件列表 (Get Workflow Files)
        files=$(gh api "repos/$REPO_FULL/contents/.github/workflows?ref=$branch" --jq '.[].name' 2>/dev/null)

        for file in $files; do
            [[ ! "$file" =~ \.(yml|yaml)$ ]] && continue

            content_json=$(gh api "repos/$REPO_FULL/contents/.github/workflows/$file?ref=$branch" 2>/dev/null)
            [ -z "$content_json" ] && continue

            content=$(echo "$content_json" | jq -r '.content' | base64 -d 2>/dev/null)

            has_pypi="❌"
            has_apt="❌"

            # 检查 PyPI 缓存 (Check PyPI Cache)
            if echo "$content" | grep -q "$PYPI_KEYWORD"; then
                has_pypi="✅"
            fi

            # 检查 APT 缓存 (Check APT Cache)
            if echo "$content" | grep -Eq "$APT_PATTERN"; then
                has_apt="✅"
            fi

            # 输出结果行 (Output Result Row)
            if [ "$has_pypi" = "✅" ] || [ "$has_apt" = "✅" ]; then
                if [ "$repo_printed" = false ]; then
                    echo "| $REPO_FULL | $branch | $file | $has_pypi | $has_apt |"
                    repo_printed=true
                else
                    echo "| | $branch | $file | $has_pypi | $has_apt |"
                fi
                if [ "$branch" == "$default_branch" ]; then
                    repo_done=true
                fi
            fi
        done

        if [ "$repo_done" = true ]; then
            break
        fi
    done

    # 兜底显示 (Fallback Display)
    if [ "$repo_printed" = false ]; then
        echo "| $REPO_FULL | (all branches) | - | ❌ | ❌ |"
    fi

done < "$INPUT_FILE"

echo -e "\nAudit complete."
