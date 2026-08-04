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

# ---------- 读取 repos.txt 默认值 ----------
# 格式: org/repo|workflow.yml|pypi_default|apt_default|ccache_default|uv_default
defaults = {}  # repo -> (pypi_default, apt_default, ccache_default, uv_default)

with open(REPOS_FILE) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        repo    = parts[0].strip()
        pypi    = parts[2].strip() if len(parts) > 2 else ""
        apt     = parts[3].strip() if len(parts) > 3 else ""
        ccache  = parts[4].strip() if len(parts) > 4 else ""
        uv      = parts[5].strip() if len(parts) > 5 else ""
        defaults[repo] = (pypi or None, apt or None, ccache or None, uv or None)

# ---------- 解析审计结果 ----------
# 格式: | repo | run | runner | PyPI 缓存 | APT 缓存 | CCache | uv | 证据 |
audit_results = {}  # repo -> (pypi, apt, ccache, uv)


def resolve(val, default):
    """Resolve cache status from script output, trusting the script's verdict.

    ✅ → ✅  (confirmed in use)
    ❌ → ❌  (confirmed NOT in use)
    -  → default (unknown, fall back to repos.txt default if available)
    """
    if val == "\u2705":  # ✅
        return "\u2705"
    if val == "\u274c":  # ❌
        return "\u274c"
    return default  # None = unknown


with open(AUDIT_FILE) as f:
    for line in f:
        if not line.startswith("| "):
            continue
        cols = [c.strip() for c in line.split("|")]
        if len(cols) < 9:
            continue
        repo_col = cols[1]

        # 提取 org/repo（去掉 markdown 链接格式）
        m = re.search(r'([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)', repo_col)
        if not m:
            continue
        repo = m.group(1)

        pypi_col   = cols[4]
        apt_col    = cols[5]
        ccache_col = cols[6]
        uv_col     = cols[7]

        defs = defaults.get(repo, (None, None, None, None))
        pypi   = resolve(pypi_col,   defs[0])
        apt    = resolve(apt_col,    defs[1])
        ccache = resolve(ccache_col, defs[2])
        uv     = resolve(uv_col,     defs[3])
        audit_results[repo] = (pypi, apt, ccache, uv)

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
rows.append("| Repository | PyPI Cache | APT Cache | CCache | uv | Last Checked |")
rows.append("| :--- | :---: | :---: | :---: | :---: | :--- |")

for repo in repos_ordered:
    pypi, apt, ccache, uv = audit_results.get(repo, (None, None, None, None))
    defs = defaults.get(repo, (None, None, None, None))
    if pypi   is None: pypi   = defs[0]
    if apt    is None: apt    = defs[1]
    if ccache is None: ccache = defs[2]
    if uv     is None: uv     = defs[3]
    rows.append(
        f"| [{repo}](https://github.com/{repo}) "
        f"| {fmt(pypi)} | {fmt(apt)} | {fmt(ccache)} | {fmt(uv)} | {TODAY} |"
    )

new_table = "\n".join([TABLE_START] + rows + [TABLE_END])

# 构建注释行
if RUN_URL:
    footer = f"> Cache audit runs daily. \u2705 = confirmed in use \u00b7 \u274c = confirmed NOT in use \u00b7 - = unknown \u00b7 Results sourced from [{RUN_URL}]({RUN_URL})"
else:
    footer = "> Cache audit runs daily. \u2705 = confirmed in use \u00b7 \u274c = confirmed NOT in use \u00b7 - = unknown"

FOOTER_RE = re.compile(r'^> (Cache audit runs daily|缓存状态每日自动审计更新)[.。].*$', re.MULTILINE)

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
