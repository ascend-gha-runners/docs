#!/usr/bin/env python3
"""
从审计结果更新 docs/Repo.md 中的缓存状态表格。

用法：
  python3 update_repo_md.py <audit_result.md> <repos.txt> <docs/Repo.md> [run_url]
"""

import re
import sys
from datetime import datetime, timezone, timedelta

AUDIT_FILE = sys.argv[1]
REPOS_FILE = sys.argv[2]
REPO_MD    = sys.argv[3]
RUN_URL    = sys.argv[4] if len(sys.argv) > 4 else None

CST = timezone(timedelta(hours=8))
TODAY = datetime.now(CST).strftime("%Y-%m-%d")

TABLE_START = "<!-- CACHE_AUDIT_TABLE_START -->"
TABLE_END   = "<!-- CACHE_AUDIT_TABLE_END -->"

# 内网 IP/域名前缀，检测到则视为已接入缓存
INTRANET_PATTERNS = [
    r'192\.168\.',
    r'10\.',
    r'172\.(1[6-9]|2[0-9]|3[01])\.',
    r'localhost',
    r'\.svc\.cluster\.local',
    r'\.internal',
]
INTRANET_RE = re.compile('|'.join(INTRANET_PATTERNS))

# ---------- 读取 repos.txt 默认值 ----------
defaults = {}  # repo -> (pypi_default, apt_default)
workflow_map = {}  # repo -> workflow_file (unused here, for reference)

with open(REPOS_FILE) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        repo = parts[0].strip()
        wf   = parts[1].strip() if len(parts) > 1 else ""
        pypi = parts[2].strip() if len(parts) > 2 else ""
        apt  = parts[3].strip() if len(parts) > 3 else ""
        workflow_map[repo] = wf
        defaults[repo] = (pypi or None, apt or None)

# ---------- 解析审计结果 ----------
# 格式：| repo | run | runner | PyPI 缓存 | APT 缓存 | 证据 |
audit_results = {}  # repo -> (pypi, apt)

UNDECIDED = {"⚙️", "⚠️", "🔍"}

with open(AUDIT_FILE) as f:
    for line in f:
        if not line.startswith("| "):
            continue
        cols = [c.strip() for c in line.split("|")]
        if len(cols) < 7:
            continue
        repo_col = cols[1]
        pypi_col = cols[4]
        apt_col  = cols[5]

        # 提取 org/repo（去掉 markdown 链接格式）
        m = re.search(r'([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)', repo_col)
        if not m:
            continue
        repo = m.group(1)

        evidence_col = cols[6] if len(cols) > 6 else ""

        def resolve(val, evidence, default):
            if val == "✅":
                return "✅"
            if val == "❌":
                # ❌ 但证据里有内网 IP/域名，视为已接入
                if INTRANET_RE.search(evidence):
                    return "✅"
                return "❌"
            # ⚙️/⚠️/🔍 不确定，用默认值
            return default  # None = 不知道

        pypi = resolve(pypi_col, evidence_col, defaults.get(repo, (None, None))[0])
        apt  = resolve(apt_col,  evidence_col, defaults.get(repo, (None, None))[1])
        audit_results[repo] = (pypi, apt)

# ---------- 读取 Repo.md，提取仓库顺序 ----------
with open(REPO_MD) as f:
    content = f.read()

# 从现有表格或链接提取仓库列表（保持顺序）
repos_in_md = re.findall(r'\[([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)\]\(https://github\.com/', content)
# 去重保序
seen = set()
repos_ordered = []
for r in repos_in_md:
    if r not in seen:
        seen.add(r)
        repos_ordered.append(r)

# ---------- 生成新表格 ----------
def fmt(val):
    if val is None:
        return "-"
    return val

rows = []
rows.append("| Repository | PyPI Cache | APT Cache | Last Checked |")
rows.append("| :--- | :---: | :---: | :--- |")

for repo in repos_ordered:
    pypi, apt = audit_results.get(repo, (None, None))
    # 如果审计没拿到值，用默认值
    if pypi is None:
        pypi = defaults.get(repo, (None, None))[0]
    if apt is None:
        apt = defaults.get(repo, (None, None))[1]
    rows.append(
        f"| [{repo}](https://github.com/{repo}) "
        f"| {fmt(pypi)} | {fmt(apt)} | {TODAY} |"
    )

new_table = "\n".join([TABLE_START] + rows + [TABLE_END])

# 构建注释行
if RUN_URL:
    footer = f"> 缓存状态每日自动审计更新。若对结果有疑问，可查看 [最新审计日志]({RUN_URL}) 了解详情。\n> ✅ = 已确认接入 · ❌ = 已确认未接入 · - = 暂无数据"
else:
    footer = "> 缓存状态每日自动审计更新。\n> ✅ = 已确认接入 · ❌ = 已确认未接入 · - = 暂无数据"

FOOTER_RE = re.compile(r'^> (Cache audit runs daily|缓存状态每日自动审计更新)\..*$', re.MULTILINE)

# ---------- 替换 Repo.md 中的表格区域 ----------
if TABLE_START in content and TABLE_END in content:
    new_content = re.sub(
        re.escape(TABLE_START) + r".*?" + re.escape(TABLE_END),
        new_table,
        content,
        flags=re.DOTALL
    )
else:
    new_content = content.rstrip() + "\n\n" + new_table + "\n"

# 替换或添加 footer
if FOOTER_RE.search(new_content):
    new_content = FOOTER_RE.sub(footer, new_content)
else:
    new_content = new_content.rstrip() + "\n\n" + footer + "\n"

with open(REPO_MD, "w") as f:
    f.write(new_content)

print(f"Updated {REPO_MD} with {len(repos_ordered)} repos ({TODAY})")
