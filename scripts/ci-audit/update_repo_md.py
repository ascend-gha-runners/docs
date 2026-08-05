#!/usr/bin/env python3
"""
从审计结果更新 docs/Repo.md 中的缓存状态表格。

用法：
  python3 update_repo_md.py <audit_result.md> <repos.txt> <docs/Repo.md> [run_url] [incremental]

模式：
  全量（默认）：用脚本输出覆盖所有仓库的所有格子
  增量（incremental=true）：只更新脚本找到 ✅/❌ 的格子，其余保留 Repo.md 旧值
"""

import re
import sys
from datetime import datetime, timezone, timedelta

AUDIT_FILE   = sys.argv[1]
REPOS_FILE   = sys.argv[2]
REPO_MD      = sys.argv[3]
RUN_URL      = sys.argv[4] if len(sys.argv) > 4 else None
INCREMENTAL  = len(sys.argv) > 5 and sys.argv[5].lower() in ('true', '1', 'yes')

CST = timezone(timedelta(hours=8))
TODAY = datetime.now(CST).strftime("%Y-%m-%d")

TABLE_START = "<!-- CACHE_AUDIT_TABLE_START -->"
TABLE_END   = "<!-- CACHE_AUDIT_TABLE_END -->"

CHECK_MARK = "\u2705"  # ✅
CROSS_MARK = "\u274c"  # ❌

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

# ---------- 读取 Repo.md ----------
with open(REPO_MD) as f:
    content = f.read()

# ---------- 解析现有表格值（增量模式用） ----------
# repo -> (pypi, apt, ccache, uv, date)  全是字符串
existing = {}
if TABLE_START in content and TABLE_END in content:
    m = re.search(re.escape(TABLE_START) + r"(.*?)" + re.escape(TABLE_END), content, re.DOTALL)
    if m:
        for line in m.group(1).split("\n"):
            if not line.startswith("| "):
                continue
            cols = [c.strip() for c in line.split("|")]
            if len(cols) < 9:
                continue
            if "Repository" in cols[1] or "---" in cols[1]:
                continue
            rm = re.search(r'([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)', cols[1])
            if rm:
                repo = rm.group(1)
                existing[repo] = (cols[4], cols[5], cols[6], cols[7],
                                   cols[8] if len(cols) > 8 else TODAY)

# ---------- 解析审计结果（原始脚本输出） ----------
raw_results = {}  # repo -> (pypi, apt, ccache, uv)

with open(AUDIT_FILE) as f:
    for line in f:
        if not line.startswith("| "):
            continue
        cols = [c.strip() for c in line.split("|")]
        if len(cols) < 9:
            continue
        rm = re.search(r'([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)', cols[1])
        if not rm:
            continue
        repo = rm.group(1)
        raw_results[repo] = (cols[4], cols[5], cols[6], cols[7])

# ---------- 提取仓库顺序（从 Repo.md 链接） ----------
repos_in_md = re.findall(r'\[([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)\]\(https://github\.com/', content)
seen = set()
repos_ordered = []
for r in repos_in_md:
    if r not in seen:
        seen.add(r)
        repos_ordered.append(r)

# ---------- 工具函数 ----------
def fmt(val):
    if val is None:
        return "-"
    return val

def resolve_cell(raw_val, old_val, default_val):
    """解析单个缓存格子的值。

    返回 (value, updated):
      updated=True  → 脚本找到了证据（✅ 或 ❌），值已更新
      updated=False → 脚本未找到证据（-），值来自旧值或默认值
    """
    if raw_val == CHECK_MARK:
        return CHECK_MARK, True
    if raw_val == CROSS_MARK:
        return CROSS_MARK, True
    # 脚本说 "-"（未找到证据）
    if INCREMENTAL:
        # 增量模式：保留 Repo.md 旧值（如果旧值有意义）
        if old_val and old_val != "-":
            return old_val, False
        # 旧值也是 "-"，尝试 repos.txt 默认值
        return default_val, False
    else:
        # 全量模式：用默认值
        return default_val, True

# ---------- 生成新表格 ----------
rows = []
rows.append("| Repository | PyPI Cache | APT Cache | CCache | uv | Last Checked |")
rows.append("| :--- | :---: | :---: | :---: | :---: | :--- |")

for repo in repos_ordered:
    raw = raw_results.get(repo, ("-", "-", "-", "-"))
    old = existing.get(repo, ("-", "-", "-", "-", TODAY))
    defs = defaults.get(repo, (None, None, None, None))

    pypi,   p_upd = resolve_cell(raw[0], old[0], defs[0])
    apt,    a_upd = resolve_cell(raw[1], old[1], defs[1])
    ccache, c_upd = resolve_cell(raw[2], old[2], defs[2])
    uv,     u_upd = resolve_cell(raw[3], old[3], defs[3])

    any_updated = p_upd or a_upd or c_upd or u_upd

    if INCREMENTAL and not any_updated and repo in existing:
        # 增量模式且无新证据 → 保留旧日期
        date = old[4]
    else:
        date = TODAY

    rows.append(
        f"| [{repo}](https://github.com/{repo}) "
        f"| {fmt(pypi)} | {fmt(apt)} | {fmt(ccache)} | {fmt(uv)} | {date} |"
    )

new_table = "\n".join([TABLE_START] + rows + [TABLE_END])

# ---------- 构建注释行 ----------
mode_label = "incremental" if INCREMENTAL else "full scan"
if RUN_URL:
    footer = (f"> Cache audit runs daily ({mode_label}). "
              f"{CHECK_MARK} = confirmed in use "
              f"\u00b7 {CROSS_MARK} = confirmed NOT in use "
              f"\u00b7 - = unknown "
              f"\u00b7 Results sourced from [{RUN_URL}]({RUN_URL})")
else:
    footer = (f"> Cache audit runs daily ({mode_label}). "
              f"{CHECK_MARK} = confirmed in use "
              f"\u00b7 {CROSS_MARK} = confirmed NOT in use "
              f"\u00b7 - = unknown")

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

mode_str = "incremental" if INCREMENTAL else "full scan"
print(f"Updated {REPO_MD} with {len(repos_ordered)} repos ({TODAY}, {mode_str})")
