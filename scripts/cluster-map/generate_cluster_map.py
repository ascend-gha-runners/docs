#!/usr/bin/env python3
"""
Cluster map is derived FROM PROJECTS: iterate projects/{org}/{repo}/{runner}/,
map each runner dir to its cluster via the ArgoCD Application that references it
(source.path -> spec.destination.name). This is the trustworthy direction — the
argocd/clusters/ directory listing itself is not authoritative.

For each runner dir read values.yaml for:
  - scaleSetLabels (capability labels, minus cluster short-names)
  - required-npu-count
  - npu-resource-model

Generates docs/Cluster.md as a card grid, main clusters first, then a divider
and the remaining ("other") clusters.

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
PROJECTS_DIR = "projects"
OUT_FILE = "docs/Cluster.md"

TOKEN = os.environ.get("GH_TOKEN", "")

# scaleSetLabels cluster labels (short names), excluded from runner capability labels
CLUSTER_SHORTNAMES = {
    "gy-001", "gy-002", "gy-003", "gy-004", "gy-005", "gy-006", "gy-007",
    "hk-001", "hk-ci", "cn12-001", "sh-001",
    "guiyang-001", "guiyang-003", "guiyang-004", "guiyang-005", "guiyang-006",
    "hb-003", "huabei-003", "verl-suzhou", "suzhou", "in-cluster",
}

# main clusters (guiyang/hongkong/shanghai/cn12) shown first; the rest grouped
# after a divider (e.g. huabei-003, verl-hb3, suzhou)
MAIN_CLUSTERS = {
    "openmerlin-guiyang-003-cluster",
    "openmerlin-guiyang-004-cluster",
    "openmerlin-guiyang-005-cluster",
    "ascend-infra-guiyang-cluster-001",
    "ascend-hk-001-cluster",
    "openmerlin-sh-001-cluster",
    "ascend-cn12-001-cluster",
}


# ---------------------------------------------------------------------------
# GitHub API
# ---------------------------------------------------------------------------

def _api(path, *, accept="application/vnd.github+json"):
    url = f"https://api.github.com{path}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", accept)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:  # nosec B310
                return json.loads(resp.read()), resp.status
        except urllib.error.HTTPError as exc:
            body = exc.read()
            try:
                return json.loads(body), exc.code
            except Exception:
                return {"message": body.decode(errors="replace")}, exc.code
        except (urllib.error.URLError, TimeoutError, OSError):
            if attempt == 2:
                raise
    return {"message": "unreachable"}, 500


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

def build_app_index():
    """source.path -> destination.name for every projects/ Application."""
    index = {}
    for entry in list_dir(CLUSTERS_DIR):
        if entry.get("type") != "dir":
            continue
        dir_name = entry["name"]
        for f in list_dir(f"{CLUSTERS_DIR}/{dir_name}"):
            if f.get("type") != "file" or not f["name"].endswith(".yaml"):
                continue
            content = get_file_content(f"{CLUSTERS_DIR}/{dir_name}/{f['name']}")
            if not content:
                continue
            for app in parse_applications(content):
                index.setdefault(app["source_path"], app["destination_name"])
    return index


def scan_clusters():
    """
    Reverse-map: iterate projects/{org}/{repo}/{runner}/, map each runner dir to
    its cluster via the ArgoCD Application referencing it.

    Returns dict: {destination_name -> {project -> [runner_info, ...]}}
    runner_info = {runner_dir, labels, npu_count, npu_model}
    """
    index = build_app_index()
    clusters = {}  # dest_name -> {project -> [runner_info]}

    for org in list_dir(PROJECTS_DIR):
        if org.get("type") != "dir":
            continue
        org_name = org["name"]
        for repo in list_dir(f"{PROJECTS_DIR}/{org_name}"):
            if repo.get("type") != "dir":
                continue
            repo_name = repo["name"]
            project = f"{org_name}/{repo_name}"
            for sub in list_dir(f"{PROJECTS_DIR}/{org_name}/{repo_name}"):
                if sub.get("type") != "dir":
                    continue
                runner_dir = sub["name"]
                if not runner_dir.startswith("linux-"):
                    continue
                rel = f"{PROJECTS_DIR}/{org_name}/{repo_name}/{runner_dir}"
                dest = index.get(rel)
                if not dest:
                    # runner dir not referenced by any ArgoCD Application
                    # (e.g. sgl-kernel-npu linux-arm64-npu-*): skip
                    continue

                values_text = get_file_content(f"{rel}/values.yaml")
                labels, npu_count, npu_model = parse_values_yaml(values_text)

                # real GitHub org/repo from githubConfigUrl (dir name is often stale)
                repo_full = ""
                if values_text:
                    m = re.search(
                        r"githubConfigUrl:\s*https?://github\.com/([^/\s]+)/([^/\s]+)",
                        values_text,
                    )
                    if m:
                        repo_full = f"{m.group(1)}/{m.group(2).rstrip('/')}"

                # capability labels = scaleSetLabels minus cluster short-names
                # (sub-model labels like a3-560t are kept)
                cap_labels = [lbl for lbl in labels if lbl not in CLUSTER_SHORTNAMES]
                if not cap_labels and labels:
                    cap_labels = [runner_dir]

                runner_info = {
                    "runner_dir": runner_dir,
                    "labels": cap_labels,
                    "npu_count": npu_count or "-",
                    "npu_model": npu_model or "-",
                    "repo_full": repo_full,
                }

                clusters.setdefault(dest, {}).setdefault(project, []).append(runner_info)

    return clusters


# ---------------------------------------------------------------------------
# Cluster map generation (HTML card grid)
# ---------------------------------------------------------------------------

def _esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def _project_display(project, runners):
    """Display name for a project: real repo from githubConfigUrl, else dir name."""
    for r in runners:
        if r.get("repo_full"):
            return r["repo_full"]
    return project


def _machine(runner):
    """One machine row: label + NPU/cpu/on-demand suffix."""
    labels = [l.rstrip("-") for l in runner["labels"]] if runner["labels"] else [runner["runner_dir"]]
    label_txt = " + ".join(labels)
    model = runner["npu_model"]
    count = runner["npu_count"]
    if _machine_bucket(runner) == "on-demand":
        # -0 pool: multi-machine / on-demand, business starts pods itself
        suffix = " · on-demand"
        cls = " machine--ondemand"
    elif not model or model in ("-", ""):
        suffix = " · cpu"
        cls = " machine--cpu"
    else:
        suffix = f" · {count} × {model}" if count and count != "-" else f" · {model}"
        cls = ""
    npu_bucket = _machine_bucket(runner)
    return (
        f'<div class="machine{cls}" data-label="{_esc(runner["runner_dir"])}" '
        f'data-npu="{_esc(npu_bucket)}">'
        f'<span class="machine-label">{_esc(label_txt)}</span>'
        f'<span class="machine-npu">{_esc(suffix)}</span></div>'
    )


def _npu_bucket(model, count):
    """Group runner into hardware bucket for filtering/statistics."""
    if not model or model in ("-", ""):
        return "cpu"
    return model


def _machine_bucket(runner):
    """Unified bucket for a runner: on-demand pools, CPU-only, or NPU model."""
    if re.search(r"-0(?:-|$)", runner["runner_dir"]):
        return "on-demand"
    if not runner["npu_model"] or runner["npu_model"] in ("-", ""):
        return "cpu"
    return runner["npu_model"]


def _collect_stats(clusters):
    """Compute counts and NPU-model distribution across all clusters."""
    projects = set()
    model_counts = {}
    total_npu = 0
    for dest, proj_map in clusters.items():
        for project, runners in proj_map.items():
            projects.add(project)
            for r in runners:
                bucket = _machine_bucket(r)
                model_counts[bucket] = model_counts.get(bucket, 0) + 1
                if bucket not in ("cpu", "on-demand") and r["npu_count"] not in ("-", ""):
                    try:
                        total_npu += int(r["npu_count"])
                    except ValueError:
                        pass
    return projects, model_counts, total_npu


def render_cluster_md(clusters):
    lines = [
        "# Cluster & Project Map",
        "",
        "Cluster-to-project mapping derived from",
        "[`opensourceways/ascend-ci-deployment`](https://github.com/opensourceways/ascend-ci-deployment) "
        "project runner configs and their ArgoCD Applications.",
        "",
        "<!-- CLUSTER_MAP_START -->",
    ]

    if not clusters:
        lines.append("<p><em>No active runner deployments found.</em></p>")
        lines.append("")
        lines.append("<!-- CLUSTER_MAP_END -->")
        return "\n".join(lines) + "\n"

    total_runners = sum(len(r) for ps in clusters.values() for r in ps.values())
    all_projects, model_counts, total_npu = _collect_stats(clusters)

    # --- legend (front) ---------------------------------------------------
    lines.append(
        '<p class="cluster-legend">Each row is one machine: <code>runner label</code> · '
        "<code>N × NPU model</code>. "
        "<code>· cpu</code> = CPU-only · <code>· on-demand</code> = elastic pool "
        "(business starts pods itself). Click a project to show its machines.</p>"
    )

    # --- stats bar -------------------------------------------------------
    lines.append('<div class="cluster-stats">')
    for num, label in (
        (len(clusters), "Clusters"),
        (len(all_projects), "Projects"),
        (total_runners, "Runners"),
        (total_npu, "NPU chips"),
    ):
        lines.append('  <div class="stat-card">')
        lines.append(f'    <span class="stat-num">{num}</span>')
        lines.append(f'    <span class="stat-label">{label}</span>')
        lines.append("  </div>")
    lines.append("</div>")

    # --- filter toolbar --------------------------------------------------
    lines.append('<div class="cluster-toolbar">')
    lines.append(
        '<input type="search" id="cluster-filter" class="cluster-filter" '
        'placeholder="Filter clusters, projects or runners…" aria-label="Filter clusters">'
    )
    lines.append('<select id="cluster-npu" class="cluster-npu-filter" aria-label="Filter by hardware">')
    lines.append(f'  <option value="">All hardware</option>')
    for bucket in sorted(model_counts.keys(), key=lambda b: (-model_counts[b], b)):
        if bucket == "cpu":
            lines.append(f'  <option value="cpu">CPU (no NPU) · {model_counts[bucket]}</option>')
        else:
            lines.append(f'  <option value="{_esc(bucket)}">{_esc(bucket)} · {model_counts[bucket]}</option>')
    lines.append("</select>")
    lines.append(
        f'<span class="cluster-hint">{len(clusters)} clusters · {total_runners} runners</span>'
    )
    lines.append("</div>")

    # --- card grid (main clusters, then divider + other clusters) --------
    lines.append('<div class="cluster-grid" id="cluster-grid">')
    lines.append("")

    main_dests = sorted(d for d in clusters if d in MAIN_CLUSTERS)
    other_dests = sorted(d for d in clusters if d not in MAIN_CLUSTERS)

    divider_emitted = False
    for dest in main_dests + other_dests:
        if dest in other_dests and not divider_emitted:
            # divider before the "other" group (only when both groups exist)
            lines.append('<div class="cluster-divider">Other clusters</div>')
            divider_emitted = True

        projects = clusters[dest]
        n_proj = len(projects)
        n_run = sum(len(r) for r in projects.values())

        lines.append(f'<div class="cluster-card" data-name="{_esc(dest)}">')
        lines.append('  <div class="cluster-card-header">')
        lines.append(f'    <span class="cluster-name">{_esc(dest)}</span>')
        lines.append(
            f'    <span class="cluster-meta">{n_proj} project{"s" if n_proj != 1 else ""} · {n_run} runner{"s" if n_run != 1 else ""}</span>'
        )
        lines.append("  </div>")
        lines.append('  <div class="cluster-body">')

        for project in sorted(projects.keys()):
            # sort by label length first, then alphabetically (a3-2, a3-4, a3-8, a3-16)
            runners = sorted(projects[project], key=lambda r: (len(r["runner_dir"]), r["runner_dir"]))
            machines = "".join(f"        {_machine(r)}" for r in runners)
            display = _project_display(project, runners)

            # searchable text: display name + all runner labels
            label_text = " ".join(
                (l.rstrip("-") for r in runners for l in (r["labels"] or [r["runner_dir"]]))
            )
            search_text = f"{display} {label_text}"

            n_machines = len(runners)
            lines.append(f'    <div class="project-row" data-search="{_esc(search_text)}">')
            lines.append('      <div class="project-line">')
            lines.append('        <button type="button" class="project-head" aria-expanded="false">')
            lines.append('          <span class="project-toggle"></span>')
            lines.append(f'          <span class="project-name-text">{_esc(display)}</span>')
            lines.append(
                f'          <span class="project-count">{n_machines} machine{"s" if n_machines != 1 else ""}</span>'
            )
            lines.append("        </button>")
            lines.append(
                f'        <a class="project-link" href="https://github.com/{_esc(display)}" '
                'target="_blank" rel="noopener" title="Open on GitHub">↗</a>'
            )
            lines.append("      </div>")
            lines.append('      <div class="machine-list" hidden>')
            lines.append(machines)
            lines.append("      </div>")
            lines.append("    </div>")

        lines.append("  </div>")
        lines.append("</div>")
        lines.append("")

    lines.append("</div>")

    # --- empty state (shown by JS only when filters match nothing) --------
    lines.append(
        '<div class="cluster-empty" id="cluster-empty" hidden>'
        "<p>No matching clusters.</p>"
        "</div>"
    )

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
