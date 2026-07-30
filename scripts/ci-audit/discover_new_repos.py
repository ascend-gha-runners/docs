#!/usr/bin/env python3
"""
Scan opensourceways/ascend-ci-deployment projects/ via GitHub API.
For each project dir not yet in docs/Repo.md:
  - resolve the real GitHub repo name (values.yaml githubConfigUrl + API canonicalization)
  - append a new row to docs/Repo.md and scripts/ci-audit/repos.txt

Writes discovered new repos to /tmp/new_repos.txt for downstream steps.
Sets GITHUB_OUTPUT has_new=true|false.

Auth: GH_TOKEN env var (CACHE_AUDIT_TOKEN, already configured in the audit workflow).
"""
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

DEPLOY_REPO = "opensourceways/ascend-ci-deployment"
TABLE_END   = "<!-- CACHE_AUDIT_TABLE_END -->"
URL_RE      = re.compile(
    r"githubConfigUrl:\s*https?://github\.com/([^/\s]+)/([^/\s]+)"
)
TOKEN = os.environ.get("GH_TOKEN", "")


# ---------------------------------------------------------------------------
# GitHub API helper
# ---------------------------------------------------------------------------

def _api(path):
    url = f"https://api.github.com{path}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:  # nosec B310
            return json.loads(resp.read()), resp.status
    except urllib.error.HTTPError as exc:
        return json.loads(exc.read() or b"{}"), exc.code


def list_dir(path):
    """Return names of subdirectories at the given repo path."""
    data, status = _api(f"/repos/{DEPLOY_REPO}/contents/{path}")
    if status != 200:
        return []
    return [item["name"] for item in data if item["type"] == "dir"]


# ---------------------------------------------------------------------------
# Repo name resolution
# ---------------------------------------------------------------------------

def _url_from_values(org, repo):
    """Fetch one values.yaml from a runner subdir and extract githubConfigUrl."""
    runner_dirs = list_dir(f"projects/{org}/{repo}")
    for rdir in runner_dirs:
        data, status = _api(
            f"/repos/{DEPLOY_REPO}/contents/projects/{org}/{repo}/{rdir}/values.yaml"
        )
        if status != 200:
            continue
        content = base64.b64decode(data.get("content", "")).decode("utf-8", errors="ignore")
        m = URL_RE.search(content)
        if m:
            return f"{m.group(1)}/{m.group(2).rstrip('/')}"
    return None


def _canonical(candidate):
    """Return GitHub's canonical full_name for a repo, or None if not found."""
    data, status = _api(f"/repos/{candidate}")
    if status == 200:
        return data.get("full_name")
    return None


def resolve_repo(org, repo):
    """
    Resolve the real GitHub org/repo for a deployment directory.

    Priority: githubConfigUrl (API-canonicalized) → dir name (API-canonicalized)
    → dir name as-is (with warning).

    Directory names are often stale org names (e.g. volcengine/verl-omni is
    actually verl-project/verl-omni). Values.yaml URLs can also be stale but
    the GitHub API follows renames transparently.
    """
    candidates = []
    url_repo = _url_from_values(org, repo)
    if url_repo and url_repo != f"{org}/{repo}":
        candidates.append(url_repo)
    candidates.append(f"{org}/{repo}")
    for c in candidates:
        full = _canonical(c)
        if full:
            if full != f"{org}/{repo}":
                print(f"  resolved {org}/{repo} -> {full}")
            return full
    print(f"  WARN: cannot resolve {org}/{repo} via API, using dir name")
    return f"{org}/{repo}"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    # ---- Read known repos from Repo.md ----
    with open("docs/Repo.md", encoding="utf-8") as f:
        repo_md = f.read()
    known = set(re.findall(
        r"\[([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)\]\(https://github\.com/",
        repo_md,
    ))
    print(f"Known repos in Repo.md: {len(known)}")

    # ---- Scan deployment repo projects/ ----
    print(f"Scanning {DEPLOY_REPO} projects/...")
    project_dirs = []
    for org in list_dir("projects"):
        for repo in list_dir(f"projects/{org}"):
            project_dirs.append((org, repo))
    print(f"Found {len(project_dirs)} project dirs")

    # ---- Resolve and find new repos ----
    new_repos = []
    for org, repo in project_dirs:
        dir_name = f"{org}/{repo}"
        # Fast path: dir name already known → skip API calls
        if dir_name in known:
            continue
        real = resolve_repo(org, repo)
        if real not in known:
            new_repos.append(real)
            known.add(real)  # deduplicate within this run

    # ---- Write /tmp/new_repos.txt for downstream steps ----
    with open("/tmp/new_repos.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(new_repos) + ("\n" if new_repos else ""))

    github_output = os.environ.get("GITHUB_OUTPUT", "")
    if not new_repos:
        print("No new repos found.")
        if github_output:
            with open(github_output, "a") as f:
                f.write("has_new=false\n")
        return

    print(f"New repos to add: {new_repos}")

    # ---- Update Repo.md ----
    today = datetime.now(timezone(timedelta(hours=8))).strftime("%Y-%m-%d")
    new_rows = "".join(
        f"| [{r}](https://github.com/{r}) | - | - | - | - | {today} |\n"
        for r in new_repos
    )
    if TABLE_END in repo_md:
        repo_md = repo_md.replace(TABLE_END, new_rows + TABLE_END)
    else:
        repo_md = repo_md.rstrip() + "\n" + new_rows
    with open("docs/Repo.md", "w", encoding="utf-8") as f:
        f.write(repo_md)
    print(f"Inserted {len(new_repos)} row(s) into docs/Repo.md")

    # ---- Update repos.txt ----
    with open("scripts/ci-audit/repos.txt", encoding="utf-8") as f:
        repos_txt = f.read()
    existing = set(repos_txt.strip().splitlines())
    additions = []
    for r in new_repos:
        line = f"{r}|||||"
        if line not in existing and not any(
            ln.startswith(f"{r}|") for ln in existing
        ):
            additions.append(line)
    if additions:
        with open("scripts/ci-audit/repos.txt", "a", encoding="utf-8") as f:
            f.write("\n" + "\n".join(additions) + "\n")
        print(f"Appended {len(additions)} line(s) to repos.txt")

    if github_output:
        with open(github_output, "a") as f:
            f.write("has_new=true\n")


if __name__ == "__main__":
    main()
