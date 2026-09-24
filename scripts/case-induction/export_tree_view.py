#!/usr/bin/env python3
"""把 problem-tree.json 导出为可读的全量决策路径表，供人工检查决策树。

用法:
    python export_tree_view.py                    # 生成 case-induction/tree-view.md
    python export_tree_view.py --tree PATH --out PATH

说明:
    - 依赖仅 Python 3.7+ 标准库。
    - 从 start 节点 DFS 遍历所有 根→叶子 路径，每条路径一行表格：
      每步分支一列 → 命中案例 → 归属徽标。
    - 自动与 git HEAD 已提交的 problem-tree.json 对比：新增 / 变化的路径行在表格中
      标 🆕，并在下方生成可勾选的复查清单；已有路径无需重复检查。
    - 每次修改 problem-tree.json 后重新生成本文件即可，无需手工维护。
"""

import argparse
import datetime
import json
import os
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_TREE = os.path.join(REPO_ROOT, "docs", "assets", "problem-tree.json")
DEFAULT_OUT = os.path.join(REPO_ROOT, "case-induction", "tree-view.md")

# 与 docs/javascripts/problem-report.js 的 LEAF_BADGES 对齐
BADGE_TEXT = {
    "check-workflow": "检查 workflow",
    "check-resource": "检查资源申请",
    "check-github": "检查 GitHub 配置",
    "ci-infra": "基础设施处理",
}


def collect_rows(tree):
    """DFS 收集所有 根→叶子 路径；返回 [(路径标签列表, 叶子节点)]。"""
    rows = []

    def walk(node_id, path_labels):
        node = tree["nodes"].get(node_id)
        if not node:
            return
        if node.get("type") == "leaf":
            rows.append((path_labels, node))
            return
        for branch in node.get("branches", []):
            walk(branch["to"], path_labels + [branch["label"]])

    walk(tree.get("start"), [])
    return rows


def row_key(path_labels, leaf):
    """一行的唯一标识：路径 + 案例标题 + 归属。任一变化都视为新增行。"""
    return (tuple(path_labels), leaf.get("title", ""),
            BADGE_TEXT.get(leaf.get("badge"), "—"))


def load_committed_rows(tree_path):
    """读取 git HEAD 中已提交的 problem-tree.json，返回已有行 key 集合。
    git 不可用或文件未提交过时返回 None（不标新增）。"""
    rel = os.path.relpath(tree_path, REPO_ROOT).replace(os.sep, "/")
    try:
        out = subprocess.run(
            ["git", "show", f"HEAD:{rel}"], cwd=REPO_ROOT,
            capture_output=True, check=True)
        old_tree = json.loads(out.stdout.decode("utf-8"))
        return {row_key(labels, leaf) for labels, leaf in collect_rows(old_tree)}
    except (subprocess.CalledProcessError, json.JSONDecodeError, OSError):
        return None


def main():
    parser = argparse.ArgumentParser(description="导出决策树全量路径表")
    parser.add_argument("--tree", default=DEFAULT_TREE, help="problem-tree.json 路径")
    parser.add_argument("--out", default=DEFAULT_OUT, help="输出 md 路径")
    args = parser.parse_args()

    with open(args.tree, encoding="utf-8") as f:
        tree = json.load(f)

    rows = collect_rows(tree)
    committed = load_committed_rows(args.tree)
    new_keys = set()
    if committed is not None:
        new_keys = {row_key(labels, leaf) for labels, leaf in rows} - committed

    max_depth = max((len(labels) for labels, _ in rows), default=0)
    step_headers = " | ".join(f"第 {i + 1} 步" for i in range(max_depth))

    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        "# 决策树全量路径表（人工检查用）",
        "",
        f"> 生成时间：{now}（由 export_tree_view.py 从 problem-tree.json 自动生成，请勿手改）",
        f"> 共 {len(rows)} 条 根→叶子 路径，其中新增 {len(new_keys)} 条（与 git HEAD 已提交版本对比）",
        "> 步骤列中与上一行相同的留空（等效合并单元格）；— 表示该路径没有这一步",
        "> 已有路径视为已检查过，人工只需复查带 🆕 的新增行（下方清单可勾选）",
        "",
        f"| {step_headers} | 命中案例 | 归属 | 人工复查 |",
        "| " + " | ".join([":---"] * (max_depth + 3)) + " |",
    ]
    prev_labels = []
    new_lines = []
    for path_labels, leaf in rows:
        key = row_key(path_labels, leaf)
        is_new = key in new_keys
        cells = []
        for i in range(max_depth):
            if i < len(path_labels):
                # 与前一行相同的前缀列留空（视觉合并）；一旦不同，后续列照写
                same_as_prev = i < len(prev_labels) and prev_labels[i] == path_labels[i]
                cells.append("" if same_as_prev else path_labels[i])
            else:
                cells.append("—")
        cells += [leaf.get("title", ""), key[2], "🆕" if is_new else ""]
        lines.append("| " + " | ".join(cells) + " |")
        if is_new:
            new_lines.append(
                f"- [ ] {' → '.join(path_labels)} → {leaf.get('title', '')}（{key[2]}）")
        prev_labels = path_labels

    lines += ["", "## 新增路径复查清单", ""]
    if new_lines:
        lines += ["> 逐条检查路径、案例与归属是否合理；确认后勾选。", ""]
        lines += new_lines
    else:
        lines.append("本期无新增路径（与已提交版本一致），无需人工复查。")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"[完成] 已生成 {args.out}（{len(rows)} 条路径，新增 {len(new_keys)} 条）")


if __name__ == "__main__":
    main()
