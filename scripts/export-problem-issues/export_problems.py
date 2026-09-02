#!/usr/bin/env python3
"""将「问题登记」创建的 issues 导出为表格，并同步仓库→runs-on 标签映射数据。

用法:
    python export_problems.py [--repo org/repo] [--label LABEL] [--out DIR] [--token TOKEN]
    python export_problems.py --map-only   # 仅根据 docs/Cluster.md 重新生成标签映射，不访问 GitHub

参数:
    --repo      仓库，默认 ascend-gha-runners/docs
    --label     筛选的 issue 标签，默认 problem-tracking
    --out       输出目录，默认当前目录
    --token     GitHub Token（也可通过环境变量 GITHUB_TOKEN / GH_TOKEN 提供）
    --no-update-map  不重新生成标签映射（默认每次导出都会从 docs/Cluster.md 同步）
    --map-only  仅更新 docs/assets/problem-labels.json 后退出（不访问 GitHub）
    --cluster-md    Cluster.md 路径（默认 docs/Cluster.md）
    --label-map     输出映射文件路径（默认 docs/assets/problem-labels.json）

说明:
    - 依赖仅 Python 3.7+ 标准库（urllib / csv / json）。
    - 问题时间 = issue 创建时间（登记页/模板自动记录，无需手动填写）。
    - 输出 problem-tracking.csv（UTF-8 BOM，Excel 可直接打开）与 problem-tracking.md（可粘贴到云文档）。
    - 私仓库必须提供 Token；公仓库可省略（受匿名限流影响）。
"""

import argparse
import csv
import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request

DEFAULT_REPO = "ascend-gha-runners/docs"
DEFAULT_LABEL = "problem-tracking"

# 仓库根目录（本脚本位于 scripts/export-problem-issues/ 下）
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_CLUSTER_MD = os.path.join(REPO_ROOT, "docs", "Cluster.md")
DEFAULT_LABEL_MAP = os.path.join(REPO_ROOT, "docs", "assets", "problem-labels.json")

# 表单字段 label -> 导出列名
FIELD_LABELS = {
    "问题社区/仓库": "问题社区/仓库",
    "runs-on 标签": "runs-on标签",
    "问题 URL": "问题URL",
    "简单描述你看到的现象": "简单描述你看到的现象",
    "提单人": "提单人",
    "定位人": "定位人",
    "定位结论": "定位结论",
    "定位时间": "定位时间",
    "问题类型": "问题类型",
}

COLUMNS = [
    "问题时间",
    "问题社区/仓库",
    "runs-on标签",
    "问题URL",
    "简单描述你看到的现象",
    "提单人",
    "定位人",
    "定位结论",
    "定位时间",
    "问题类型",
]

HEADING_RE = re.compile(r"^#{3}\s+(.+?)\s*$")  # ### 表单字段标题


def fetch_issues(repo, label, token):
    """分页拉取带指定标签的全部 issues（含已关闭）。"""
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "problem-export"}
    if token:
        headers["Authorization"] = "Bearer " + token

    issues = []
    page = 1
    while True:
        url = (
            f"https://api.github.com/repos/{repo}/issues"
            f"?state=all&per_page=100&page={page}"
            f"&labels={urllib.parse.quote(label)}"
        )
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                batch = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            sys.stderr.write(f"[错误] 请求 GitHub API 失败: HTTP {e.code} {e.reason}\n")
            sys.stderr.write(f"  可能原因: 仓库不存在 / 标签不存在 / Token 无权限 / 匿名限流\n")
            sys.exit(1)
        if not batch:
            break
        issues.extend(i for i in batch if "pull_request" not in i)  # 排除 PR
        if len(batch) < 100:
            break
        page += 1
    return issues


def parse_body(body):
    """解析 issue body，按 '### 表单字段标题' 切分为 {标题: 内容}。"""
    sections = {}
    if not body:
        return sections
    current = None
    for line in body.splitlines():
        m = HEADING_RE.match(line)
        if m:
            current = m.group(1).strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            if line.strip().startswith("```"):
                continue  # 忽略代码块围栏 ```，只保留内容
            sections[current].append(line)
    # 合并多余空行，便于 Excel 阅读
    return {k: re.sub(r"\n{2,}", "\n", "\n".join(v).strip()) for k, v in sections.items()}


def format_date(created_at):
    """把 ISO 时间 (2026-08-31T..Z) 转成 2026/8/31。"""
    try:
        dt = datetime.datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        return f"{dt.year}/{dt.month}/{dt.day}"
    except (ValueError, AttributeError):
        return (created_at or "")[:10]


def build_row(issue):
    fields = parse_body(issue.get("body", ""))
    values = [fields.get(label, "").strip() for label in FIELD_LABELS]
    return [format_date(issue.get("created_at", "")), *values]


def escape_md(value):
    """转义 Markdown 表格中的特殊字符。"""
    return value.replace("|", "\\|").replace("\r\n", "\n").replace("\n", "<br>")


def write_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(COLUMNS)
        writer.writerows(rows)
    print(f"[完成] 已生成 {path} ({len(rows)} 条)")


def write_md(path, rows):
    header = "| " + " | ".join(COLUMNS) + " |"
    sep = "| " + " | ".join(["---"] * len(COLUMNS)) + " |"
    lines = [header, sep]
    for row in rows:
        lines.append("| " + " | ".join(escape_md(c) for c in row) + " |")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"[完成] 已生成 {path} ({len(rows)} 条)")


def load_label_map(cluster_md=DEFAULT_CLUSTER_MD):
    """解析 Cluster.md：
       - repos: {仓库: [runs-on 标签, ...]}（跨集群去重，登记页下拉用）
       - label_clusters: {标签: [集群, ...]}（一个标签可能出现在多个集群，供 issue 标注对应集群）
    """
    with open(cluster_md, encoding="utf-8") as f:
        text = f.read()
    repos = {}
    label_clusters = {}
    for card in re.split(r'<div class="cluster-card"', text)[1:]:
        m = re.search(r'data-name="([^"]+)"', card)
        cluster = m.group(1).strip() if m else None
        for block in re.split(r'<div class="project-row"', card)[1:]:
            pm = re.search(r'<span class="project-name-text">([^<]+)</span>', block)
            if not pm:
                continue
            repo = pm.group(1).strip()
            labels = set(re.findall(r'data-label="([^"]+)"', block))
            if not labels:
                continue
            repos.setdefault(repo, set()).update(labels)
            if cluster:
                for lab in labels:
                    label_clusters.setdefault(lab, set()).add(cluster)
    return (
        {r: sorted(s) for r, s in repos.items()},
        {l: sorted(cs) for l, cs in label_clusters.items()},
    )


def update_label_map(cluster_md=DEFAULT_CLUSTER_MD, out_path=DEFAULT_LABEL_MAP):
    """根据 Cluster.md 重新生成 仓库→标签 与 标签→集群 映射 JSON（登记页的数据源）。"""
    repos, label_clusters = load_label_map(cluster_md)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(
            {
                "repos": dict(sorted(repos.items())),
                "labelClusters": dict(sorted(label_clusters.items())),
            },
            f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"[完成] 已更新映射 {out_path}（{len(repos)} 个仓库、{len(label_clusters)} 个标签→集群）")
    return repos


def main():
    parser = argparse.ArgumentParser(description="导出问题登记 issues 为表格")
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--label", default=DEFAULT_LABEL)
    parser.add_argument("--out", default=".")
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"))
    parser.add_argument("--cluster-md", default=DEFAULT_CLUSTER_MD)
    parser.add_argument("--label-map", default=DEFAULT_LABEL_MAP)
    parser.add_argument("--no-update-map", action="store_true", help="不重新生成标签映射")
    parser.add_argument("--map-only", action="store_true", help="仅更新标签映射后退出")
    args = parser.parse_args()

    if not args.no_update_map:
        update_label_map(args.cluster_md, args.label_map)
    if args.map_only:
        return

    issues = fetch_issues(args.repo, args.label, args.token)
    issues.sort(key=lambda i: i.get("created_at", ""))  # 按创建时间升序
    rows = [build_row(i) for i in issues]

    os.makedirs(args.out, exist_ok=True)
    write_csv(os.path.join(args.out, "problem-tracking.csv"), rows)
    write_md(os.path.join(args.out, "problem-tracking.md"), rows)
    print(f"[提示] 问题时间取自 issue 创建时间；定位字段为空表示尚未定位。")


if __name__ == "__main__":
    main()
