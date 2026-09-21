#!/usr/bin/env python3
"""根据 docs/Cluster.md 重新生成 docs/assets/problem-labels.json（问题登记页 runs-on 标签数据源）。

用法:
    python update_problem_labels.py [--cluster-md docs/Cluster.md] [--label-map docs/assets/problem-labels.json]

说明:
    - 依赖仅 Python 3.7+ 标准库（json / os / re）。
    - 产物结构: {"repos": {仓库: [runs-on 标签...]}, "labelClusters": {标签: [集群...]}}
      repos 的标签跨集群去重（登记页下拉用）；labelClusters 记录每个标签出现的集群。
    - 写入 JSON 末尾保留换行，满足 CI yamllint new-line-at-end-of-file 校验。
"""

import argparse
import json
import os
import re

# 仓库根目录（本脚本位于 scripts/problem-labels/ 下）
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_CLUSTER_MD = os.path.join(REPO_ROOT, "docs", "Cluster.md")
DEFAULT_LABEL_MAP = os.path.join(REPO_ROOT, "docs", "assets", "problem-labels.json")


def load_label_map(cluster_md):
    """解析 Cluster.md：
       - repos: {仓库: [runs-on 标签, ...]}（跨集群去重）
       - label_clusters: {标签: [集群, ...]}（一个标签可能出现在多个集群）
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


def update_label_map(cluster_md, out_path):
    """根据 Cluster.md 重新生成 仓库→标签 与 标签→集群 映射 JSON。"""
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
    parser = argparse.ArgumentParser(description="根据 Cluster.md 更新问题登记页 runs-on 标签映射")
    parser.add_argument("--cluster-md", default=DEFAULT_CLUSTER_MD)
    parser.add_argument("--label-map", default=DEFAULT_LABEL_MAP)
    args = parser.parse_args()
    update_label_map(args.cluster_md, args.label_map)


if __name__ == "__main__":
    main()