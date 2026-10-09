#!/usr/bin/env python3
"""
从审计结果更新 docs/Repo.md 中的缓存状态表格。

用法：
  python3 update_repo_md.py <audit_result.md> <repos.txt> <docs/Repo.md> [run_url] [incremental]

模式：
  全量（默认）与增量（incremental=true）行为一致：脚本找到 ✅/❌ 就更新该格子；
  脚本未找到证据（-）时优先保留 Repo.md 旧值，旧值也是 - 时才回落到 repos.txt 默认值。
  表格不再包含「Last Checked」列：审计时间统一写入表格下方的 footer 说明。
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

# 缓存维度顺序（必须与 check_cache_from_logs.sh 输出列顺序一致）
DIMS = ("pypi", "apt", "ccache", "uv", "buildkit", "squid", "runson")
TABLE_HEADER = ("| Repo | PyPI | APT | CCache | uv "
                "| BuildKit | Squid | runs-on |")
TABLE_ALIGN  = "| :--- | " + " | ".join([":---:"] * len(DIMS)) + " |"


def empty_marks():
    return tuple("-" for _ in DIMS)


# ---------- 读取 repos.txt 默认值 ----------
# 格式: org/repo|workflow.yml|pypi|apt|ccache|uv|buildkit|squid|runson
# 默认值从 parts[2] 开始，依次对应 DIMS
defaults = {}  # repo -> tuple(str|None, ...)

with open(REPOS_FILE) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        repo = parts[0].strip()
        vals = []
        for i in range(len(DIMS)):
            idx = 2 + i
            v = parts[idx].strip() if len(parts) > idx else ""
            vals.append(v or None)
        defaults[repo] = tuple(vals)

# ---------- 读取 Repo.md ----------
with open(REPO_MD) as f:
    content = f.read()

# ---------- 解析现有表格值（保留旧值用） ----------
# 新格式: | Repository | PyPI | APT | CCache | uv | BuildKit | Squid | runs-on/cache |
#          split("|") 后: cols[0]="" cols[1]=repo cols[2..2+len(DIMS)]=缓存格
# 旧格式: | Repository | PyPI | APT | CCache | uv | Last Checked |
#          （兼容迁移：只取前 4 维，其余维视为无旧值）
existing = {}
if TABLE_START in content and TABLE_END in content:
    m = re.search(re.escape(TABLE_START) + r"(.*?)" + re.escape(TABLE_END), content, re.DOTALL)
    if m:
        for line in m.group(1).split("\n"):
            if not line.startswith("| "):
                continue
            cols = [c.strip() for c in line.split("|")]
            if len(cols) < 3:
                continue
            if "Repository" in cols[1] or "---" in cols[1]:
                continue
            rm = re.search(r'([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)', cols[1])
            if not rm:
                continue
            repo = rm.group(1)
            if len(cols) >= len(DIMS) + 2:
                # 新格式（len(DIMS) 个缓存列）
                existing[repo] = tuple(cols[2:2 + len(DIMS)])
            elif len(cols) >= 8:
                # 旧格式（4 个缓存列 + Last Checked），迁移时补足为 len(DIMS) 维
                existing[repo] = tuple(cols[2:6]) + tuple("-" for _ in range(len(DIMS) - 4))

# ---------- 解析审计结果（原始脚本输出） ----------
# 审计行: | repo | run | runner | pypi | apt | ccache | uv | buildkit | squid | runson | evidence |
raw_results = {}

# newline='\n'：不把行内残留的 \r（来自日志/run 名）当作换行，避免整行被截断
with open(AUDIT_FILE, newline='\n') as f:
    for line in f:
        if not line.startswith("| "):
            continue
        cols = [c.strip() for c in line.split("|")]
        # 元素数 = 3(前缀: 空串+repo+run+runner) ... 需覆盖到最后一个缓存格
        if len(cols) < 4 + len(DIMS):
            continue
        rm = re.search(r'([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)', cols[1])
        if not rm:
            continue
        raw_results[rm.group(1)] = tuple(cols[4:4 + len(DIMS)])

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
    return "-" if val is None else val

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
    # 脚本说 "-"（未找到证据）：优先保留 Repo.md 旧值，其次回落到 repos.txt 默认值
    if old_val and old_val != "-":
        return old_val, False
    return default_val, False

# ---------- 生成新表格 ----------
rows = [TABLE_HEADER, TABLE_ALIGN]

for repo in repos_ordered:
    raw = raw_results.get(repo, empty_marks())
    old = existing.get(repo, empty_marks())
    defs = defaults.get(repo, tuple(None for _ in DIMS))

    cells = []
    for i in range(len(DIMS)):
        val, _updated = resolve_cell(raw[i], old[i], defs[i])
        cells.append(fmt(val))

    rows.append(f"| [{repo}](https://github.com/{repo}) | " + " | ".join(cells) + " |")

new_table = "\n".join([TABLE_START] + rows + [TABLE_END])

# ---------- 构建注释 footer（图例 / 时间 / 来源各自独立成行） ----------
mode_label = "incremental" if INCREMENTAL else "full scan"
footer_lines = [
    f"> Cache audit runs daily ({mode_label}).",
    ">",
    f"> {CHECK_MARK} = confirmed in use \u00b7 {CROSS_MARK} = confirmed NOT in use \u00b7 - = unknown",
    ">",
    f"> Last checked: {TODAY}",
]
if RUN_URL:
    footer_lines += [">", f"> Results sourced from [{RUN_URL}]({RUN_URL})"]
footer = "\n".join(footer_lines)

# ---------- 替换 Repo.md 中的表格区域 ----------
if TABLE_START in content and TABLE_END in content:
    new_content = re.sub(
        re.escape(TABLE_START) + r".*?" + re.escape(TABLE_END),
        new_table,
        content,
        flags=re.DOTALL
    )
else:
    new_content = content.rstrip() + "\n\n" + new_table

# footer 始终紧跟在表格之后：截断 TABLE_END 之后的所有旧内容，再追加新 footer
idx = new_content.find(TABLE_END)
if idx != -1:
    new_content = new_content[:idx + len(TABLE_END)]
new_content = new_content.rstrip() + "\n\n" + footer + "\n"

with open(REPO_MD, "w") as f:
    f.write(new_content)

print(f"Updated {REPO_MD} with {len(repos_ordered)} repos ({TODAY}, {mode_label})")
print(f"  Parsed {len(existing)} existing table rows, {len(raw_results)} audit results")
