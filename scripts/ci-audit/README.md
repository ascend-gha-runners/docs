# CI Cache Audit Script

Scan GitHub repositories integrated with our NPU runners and determine whether
their CI actually benefits from the cluster's caches (PyPI / APT / CCache / uv /
BuildKit / Squid / git-cdn / runs-on cache).

Detection strategy is documented in
[docs/cache-audit-strategy-zh.md](../../docs/cache-audit-strategy-zh.md).
In short:

- **Project-side caches** (PyPI / APT / CCache / uv / runs-on cache) are
  detected from GitHub Actions job logs (runtime evidence) plus a workflow
  static scan for runs-on/cache.
- **Infra-injected caches** (BuildKit / Squid / git-cdn) are wired by
  [ascend-ci-deployment](https://github.com/opensourceways/ascend-ci-deployment)
  pod templates and are invisible in the audited repos' workflows. Their
  authoritative signal is the deployment repo wiring (grep a local clone via
  `DEPLOY_REPO_DIR`, zero API calls); job logs only provide supplementary
  runtime evidence (e.g. `building with "buildkitd" instance using remote
  driver`, `#N CACHED`, `Runner is running behind proxy server`).

## Usage

1. `repos.txt` lists one entry per line: `org/repo` or
   `org/repo|workflow-file.yml` (targeted mode), optionally followed by 8
   default-value columns (pypi/apt/ccache/uv/buildkit/squid/gitcdn/runson).
2. Run:
   ```bash
   # with the deployment repo available (enables infra-wiring detection):
   git clone --depth 1 https://github.com/opensourceways/ascend-ci-deployment /tmp/deploy
   DEPLOY_REPO_DIR=/tmp/deploy GH_TOKEN=... \
     ./check_cache_from_logs.sh repos.txt
   ```

## Configuration

| Variable | Description | Default |
| :--- | :--- | :--- |
| `DEPLOY_REPO_DIR` | Local clone of ascend-ci-deployment; authoritative source for BuildKit/Squid/git-cdn wiring. Unset = degrade to log-only detection | unset |
| `PYPI_CACHE_HOST` | PyPI cache host to match in logs | `cache-service.nginx-pypi-cache.svc.cluster.local` |
| `APT_CACHE_PORT` | APT cache port | `8081` |
| `CCACHE_KEYWORD` | ccache detection keyword | `ccache` |
| `RUNNER_FILTER` | Runner label filter (comma separated) | `linux-aarch64,linux-amd64` |
| `MAX_NPU_SEARCH` / `MAX_CANDIDATES` / `MAX_LOGS_TO_CHECK` | Scan caps (0 = full scan mode with internal caps) | `50` / `15` / `10` |
| `PARALLEL` | Concurrent repo workers | `4` |
| `AUDIT_TOKENS` | Comma-separated read-only tokens, rotated per repo | falls back to `GH_TOKEN` |

## Output

A Markdown table with one row per repo: run/runner metadata, 8 cache marks
(✅ confirmed in use / ❌ confirmed NOT in use / `-` unknown) and the evidence
snippet that produced each mark. Consumed by `update_repo_md.py` to maintain
`docs/Repo.md`.
