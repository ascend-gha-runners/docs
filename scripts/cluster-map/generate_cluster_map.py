#!/usr/bin/env python3
"""
Scan opensourceways/ascend-ci-deployment argocd/clusters/ via GitHub API.
For each Application with source.path starting with "projects/", collect:
  - cluster: spec.destination.name
  - project: org/repo from path segments
  - runner dir: path segment after org/repo (e.g. linux-aarch64-a3-2)
Then for each runner dir, read projects/{org}/{repo}/{runner}/values.yaml to get:
  - scaleSetLabels (capability labels = all labels except the one matching cluster)
  - required-npu-count
  - npu-resource-model

Generates docs/Cluster.md with MkDocs Material content tabs, one tab per cluster.
Also git-adds the file (caller must commit).

Required env:
  GH_TOKEN   token with read access to opensourceways/ascend-ci-deployment
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

DEPLOYMENT_REPO = "opensourceways/ascend-ci-deployment"
CLUSTERS_DIR = "argocd/clusters"
OUT_FILE = "docs/Cluster.md"

TOKEN = os.environ.get("GH_TOKEN", "")


# ---------------------------------------------------------------------------
# GitHub API
# ---------------------------------------------------------------------------

def _api(path, *, accept="application/vnd.github+json"):
    url = f"https://api.github.com{path}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", accept)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:  # nosec B310
            return json.loads(resp.read()), resp.status
    except urllib.error.HTTPError as exc:
        body = exc.read()
        try:
            return json.loads(body), exc.code
        except Exception:
            return {"message": body.decode(errors="replace")}, exc.code


def list_dir(path):
    data, status = _api(f"/repos/{DEPLOYMENT_REPO}/contents/{path}")
    if status != 200:
        return []
    return data if isinstance(data, list) else []


def get_file_content(path):
    import base64
    data, status = _api(f"/repos/{DEPLOYMENT_REPO}/contents/{path}")
    if status != 200:
        return None
    raw = data.get("content", "")
    try:
        return base64.b64decode(raw).decode(errors="replace")
    except Exception:
        return None


# ---------------------------------------------------------------------------
# YAML mini-parser (no PyYAML dependency)
# ---------------------------------------------------------------------------

def _parse_sequence(lines, start):
    """Return list of string values from a YAML sequence starting at start."""
    items = []
    for line in lines[start:]:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- "):
            items.append(stripped[2:].strip().strip('"').strip("'"))
        elif not stripped.startswith("-"):
            break
    return items


def parse_values_yaml(text):
    """Extract scaleSetLabels, required-npu-count, npu-resource-model from values.yaml."""
    if not text:
        return [], None, None

    lines = text.splitlines()
    labels = []
    npu_count = None
    npu_model = None

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("scaleSetLabels:"):
            labels = _parse_sequence(lines, i + 1)
        elif "ascend-ci.com/required-npu-count:" in stripped:
            m = re.search(r'required-npu-count:\s*["\']?(\d+)["\']?', stripped)
            if m:
                npu_count = m.group(1)
        elif "ascend-ci.com/npu-resource-model:" in stripped:
            m = re.search(r'npu-resource-model:\s*["\']?([^\s"\']+)["\']?', stripped)
            if m:
                npu_model = m.group(1)

    return labels, npu_count, npu_model


# ---------------------------------------------------------------------------
# ArgoCD Application YAML parser
# ---------------------------------------------------------------------------

def parse_applications(text):
    """
    Split multi-doc YAML by '---', extract Application docs with source.path
    starting with 'projects/' (runner apps, not config apps).
    Returns list of dicts: {destination_name, source_path}
    """
    apps = []
    for doc in text.split("\n---"):
        doc = doc.strip()
        if not doc:
            continue
        if "kind: Application" not in doc:
            continue
        # destination name
        dest_m = re.search(r"destination:\s*\n(?:.*\n)*?.*?name:\s*(\S+)", doc)
        if not dest_m:
            continue
        dest_name = dest_m.group(1)

        # source path
        path_m = re.search(r"path:\s*(projects/\S+)", doc)
        if not path_m:
            continue
        source_path = path_m.group(1).rstrip("/")

        # skip config dirs (path ends with /config or /config-*)
        last_seg = source_path.split("/")[-1]
        if last_seg.startswith("config") or last_seg == "config":
            continue

        apps.append({"destination_name": dest_name, "source_path": source_path})
    return apps


# ---------------------------------------------------------------------------
# Main scan
# ---------------------------------------------------------------------------

def scan_clusters():
    """
    Returns dict: {destination_name -> {project -> [runner_info, ...]}}
    runner_info = {runner_dir, labels, npu_count, npu_model}
    """
    entries = list_dir(CLUSTERS_DIR)
    clusters = {}  # dest_name -> {project -> [runner_info]}

    for entry in entries:
        if entry.get("type") != "dir":
            continue
        dir_name = entry["name"]
        files = list_dir(f"{CLUSTERS_DIR}/{dir_name}")

        for f in files:
            if f.get("type") != "file" or not f["name"].endswith(".yaml"):
                continue
            content = get_file_content(f"{CLUSTERS_DIR}/{dir_name}/{f['name']}")
            if not content:
                continue
            apps = parse_applications(content)
            for app in apps:
                dest = app["destination_name"]
                parts = app["source_path"].split("/")
                # parts: ['projects', org, repo, runner_dir]
                if len(parts) < 4:
                    continue
                org, repo, runner_dir = parts[1], parts[2], parts[3]
                project = f"{org}/{repo}"

                # fetch values.yaml
                values_path = f"{app['source_path']}/values.yaml"
                values_text = get_file_content(values_path)
                labels, npu_count, npu_model = parse_values_yaml(values_text)

                # capability labels = all scaleSetLabels except the one matching dest
                # (cluster label is typically the short cluster suffix like "gy-005" or full dest name)
                cap_labels = [
                    lbl for lbl in labels
                    if lbl not in (dest,) and not dest.endswith(lbl) and not lbl == dir_name
                ]
                if not cap_labels and labels:
                    # fallback: use runner_dir name itself
                    cap_labels = [runner_dir]

                runner_info = {
                    "runner_dir": runner_dir,
                    "labels": cap_labels,
                    "npu_count": npu_count or "-",
                    "npu_model": npu_model or "-",
                }

                clusters.setdefault(dest, {}).setdefault(project, []).append(runner_info)

    return clusters


# ---------------------------------------------------------------------------
# Markdown generation
# ---------------------------------------------------------------------------

def render_cluster_md(clusters):
    lines = [
        "# Cluster & Project Map",
        "",
        "Cluster-to-project mapping, auto-generated daily from",
        "[`opensourceways/ascend-ci-deployment`](https://github.com/opensourceways/ascend-ci-deployment)`/argocd/clusters/`.",
        "",
        "Each tab shows one cluster and its active `projects/` runner scale sets.",
        "",
        "<!-- CLUSTER_MAP_START -->",
    ]

    if not clusters:
        lines.append("*No active runner deployments found.*")
        lines.append("")
        lines.append("<!-- CLUSTER_MAP_END -->")
        return "\n".join(lines) + "\n"

    for dest in sorted(clusters.keys()):
        projects = clusters[dest]
        lines.append(f'=== "{dest}"')
        lines.append("")

        # collect all rows first so we can emit one table per cluster
        rows = []
        for project in sorted(projects.keys()):
            runners = sorted(projects[project], key=lambda r: r["runner_dir"])
            first = True
            for r in runners:
                cap = ", ".join(l.rstrip("-") for l in r["labels"]) if r["labels"] else r["runner_dir"]
                proj_cell = f"[{project}](https://github.com/{project})" if first else ""
                rows.append((proj_cell, cap, r["npu_model"], r["npu_count"]))
                first = False

        lines.append("    | Project | Runner Labels | NPU Model | NPU Count |")
        lines.append("    | :--- | :--- | :---: | :---: |")
        for proj_cell, cap, model, count in rows:
            lines.append(f"    | {proj_cell} | `{cap}` | {model} | {count} |")
        lines.append("")

    lines.append("<!-- CLUSTER_MAP_END -->")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------

def main():
    print("Scanning deployment repo clusters...", flush=True)
    clusters = scan_clusters()
    total_runners = sum(
        len(runners)
        for projects in clusters.values()
        for runners in projects.values()
    )
    print(f"Found {len(clusters)} clusters, {total_runners} runner entries", flush=True)

    md = render_cluster_md(clusters)

    with open(OUT_FILE, "w", encoding="utf-8") as fh:
        fh.write(md)
    print(f"Written: {OUT_FILE}", flush=True)


if __name__ == "__main__":
    main()
