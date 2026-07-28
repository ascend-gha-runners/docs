# Package Cache Guide

To make CI on Ascend NPU runners faster and more reliable, our clusters run an in-cluster
caching proxy for common package managers (PyPI, APT, yum/dnf, rustup). On a cache hit,
packages are served from inside the cluster instead of being downloaded from the public
internet on every run — this avoids network flakiness, upstream rate limits, and
repeated downloads of the same wheels and `.deb`/`.rpm` files.

The cache is **opt-in**: it does not take effect automatically. You add a few setup
commands to your workflow so that `pip` / `apt` / `dnf` point at the cache service.

The [Integrated Repositories](Repo.md) page shows, per repository, whether the PyPI and
APT caches are currently in use.

## How it works

The cache is an nginx reverse proxy with on-disk storage, deployed inside the same
Kubernetes cluster as the runners. It transparently proxies upstream mirrors
(Huawei Cloud, official PyPI, PyTorch, etc.), caches the responses, and serves the cached
copy on subsequent requests.

```
┌───────────────────────────────┐      cache HIT       ┌──────────────────────────┐
│  Your CI job (runner pod /     │  ──────────────────▶ │  cache-service (nginx)   │
│  container.image)              │                      │  in-cluster, on-disk     │
│  pip / apt / dnf / rustup      │  ◀──────────────────  │  cache                   │
└───────────────────────────────┘    cached package    └────────────┬─────────────┘
                                                                     │ cache MISS
                                                                     ▼
                                                    upstream mirrors (Huawei Cloud,
                                                    pypi.org, pytorch.org, ...)
```

!!! important
    The cache service has a **cluster-internal** address
    (`cache-service.nginx-pypi-cache.svc.cluster.local`). It is only reachable from
    **inside a running job**, i.e. from within your `container.image`. It is not
    reachable from your laptop or from GitHub-hosted runners. All the commands below are
    meant to run as steps inside an Ascend NPU runner job.

## Prerequisites

- Your repository is already onboarded to Ascend NPU runners. If not, follow the
  [GitHub Actions Integration Guide](user-manual-gha-en.md) first.
- Your job runs inside a `container.image` on an Ascend runner (see the workflow example
  at the end).

## Service endpoints

All package managers talk to the same service, `cache-service.nginx-pypi-cache.svc.cluster.local`,
on different ports:

| Package manager | Port | Endpoint |
| :--- | :---: | :--- |
| pip / PyPI | 80 | `http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple` |
| PyTorch wheels | 80 | `http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/<variant>` |
| APT (Ubuntu / Debian) | 8081 | `cache-service.nginx-pypi-cache.svc.cluster.local:8081` |
| rustup | 8082 | `http://cache-service.nginx-pypi-cache.svc.cluster.local:8082` |
| yum / dnf (openEuler) | 8083 | `http://cache-service.nginx-pypi-cache.svc.cluster.local:8083` |

---

## PyPI (pip)

**What you need to do**:

Point `pip` at the cache before installing any dependencies:

```bash
pip config set global.index-url http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
pip config set global.trusted-host cache-service.nginx-pypi-cache.svc.cluster.local
```

The `trusted-host` line is required because the cache is served over plain HTTP inside the
cluster; without it `pip` refuses the insecure index.

The PyPI cache is backed by the Huawei Cloud mirror and automatically falls back to
official `pypi.org` / `files.pythonhosted.org` when the mirror has not yet synced a freshly
published package, so you do not need a separate fallback index.

!!! tip "Using uv"
    If your project uses [uv](https://github.com/astral-sh/uv), set the equivalent
    environment variables instead of (or in addition to) the `pip config` commands:

    ```bash
    export UV_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
    export UV_INSECURE_HOST=cache-service.nginx-pypi-cache.svc.cluster.local
    ```

**How to verify**:

- `pip install` succeeds and, on a second run, completes noticeably faster.
- The response carries a cache-status header. You can check it directly:

  ```bash
  curl -sI http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple/numpy/ \
    | grep -i x-pypi-cache
  # X-Pypi-Cache: HIT   (MISS on the first request, HIT afterwards)
  ```

### PyTorch wheels (optional)

To install PyTorch and its companion wheels through the cache, use the `/whl/<variant>`
index (mirrors `download.pytorch.org/whl/<variant>`):

```bash
pip install torch --index-url http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/cpu
```

Replace `cpu` with the variant you need (e.g. `cpu`, `cu121`). The cache rewrites the
PyTorch index links so wheel downloads stay inside the cluster.

---

## APT (Ubuntu / Debian)

**What you need to do**:

Rewrite the upstream host in your APT sources to the cache (port `8081`), then run
`apt-get update` as usual. The exact file depends on the base image of your container.

=== "Ubuntu 22.04 or earlier"

    ```bash
    sed -Ei 's@(ports|archive).ubuntu.com@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list
    apt-get update
    ```

=== "Ubuntu 24.04 or later (deb822)"

    ```bash
    sed -Ei 's@(ports|archive).ubuntu.com@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list.d/ubuntu.sources
    apt-get update
    ```

=== "Debian 11 or earlier"

    ```bash
    sed -Ei 's@deb.debian.org@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list
    apt-get update
    ```

=== "Debian 12 or later (deb822)"

    ```bash
    sed -Ei 's@deb.debian.org@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list.d/debian.sources
    apt-get update
    ```

!!! note
    Newer Ubuntu/Debian images use the [deb822](https://manpages.debian.org/bookworm/dpkg-dev/deb822.5.en.html)
    format, where the sources live in `*.sources` files under `/etc/apt/sources.list.d/`
    rather than in `/etc/apt/sources.list`. If you are unsure which your image uses, check
    which file exists.

**How to verify**:

- `apt-get update` and `apt-get install` succeed, and repeated installs are faster.
- Response headers from the cache include `X-Cache-Status: HIT`.

---

## yum / dnf (openEuler)

**What you need to do**:

The cache listens on port `8083` for openEuler repos and proxies
`repo.huaweicloud.com/openeuler/...`. Replace the upstream host in every `.repo` file with
the cache service, then rebuild the metadata cache:

```bash
sed -Ei \
  -e 's@https?://repo\.openeuler\.org@http://cache-service.nginx-pypi-cache.svc.cluster.local:8083@g' \
  -e 's@https?://mirrors\.openeuler\.org@http://cache-service.nginx-pypi-cache.svc.cluster.local:8083@g' \
  /etc/yum.repos.d/*.repo
dnf clean all && dnf makecache
```

If your image already points its `baseurl` at Huawei Cloud, rewrite that host instead (the
cache strips the `/openeuler` prefix it would otherwise duplicate):

```bash
sed -Ei \
  's@https?://repo\.huaweicloud\.com/openeuler@http://cache-service.nginx-pypi-cache.svc.cluster.local:8083@g' \
  /etc/yum.repos.d/*.repo
```

!!! warning "Keep `gpgcheck=1`"
    RPM signatures are verified end-to-end, so serving packages over plain HTTP from the
    cache is safe. Do **not** turn off `gpgcheck` — that is what would actually break
    signature verification.

!!! note "metalink"
    The `metalink=` line is rewritten by the `sed` above and will return 404 from the
    cache (metalink is not proxied). `dnf` falls back to `baseurl=` automatically —
    functional, just one extra round-trip. To skip it entirely:

    ```bash
    sed -i '/^metalink=/d' /etc/yum.repos.d/*.repo
    ```

**How to verify**:

- `dnf makecache` / `dnf install` succeed against the rewritten repos.
- Response headers from the cache include `X-Yum-Cache: HIT`.

---

## rustup (optional)

**What you need to do**:

If your build installs a Rust toolchain via `rustup`, point it at the cache on port `8082`
(backed by the Huawei Cloud rustup mirror):

```bash
export RUSTUP_DIST_SERVER=http://cache-service.nginx-pypi-cache.svc.cluster.local:8082/rustup
export RUSTUP_UPDATE_ROOT=http://cache-service.nginx-pypi-cache.svc.cluster.local:8082/rustup/rustup
```

**How to verify**:

- `rustup` / `rustup-init` downloads complete, and toolchain tarballs come back faster on
  repeat runs.
- Response headers from the cache include `X-Rustup-Cache: HIT`.

---

## Full workflow example

A complete GitHub Actions workflow that runs on an Ascend NPU runner and uses the PyPI and
APT caches:

```yaml
name: NPU CI (with cache)
on:
  push:
  pull_request:
jobs:
  test:
    runs-on: linux-aarch64-a2-1
    container:
      image: ascendai/cann:latest
    steps:
      - name: Configure package caches
        run: |
          # PyPI
          pip config set global.index-url http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
          pip config set global.trusted-host cache-service.nginx-pypi-cache.svc.cluster.local
          # APT (Ubuntu 22.04 base; adjust for your image)
          sed -Ei 's@(ports|archive).ubuntu.com@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
            /etc/apt/sources.list

      - uses: actions/checkout@v4

      - name: Install system deps
        run: |
          apt-get update
          apt-get install -y --no-install-recommends git

      - name: Install Python deps
        run: pip install -r requirements.txt

      - name: Run tests
        run: |
          npu-smi info
          pytest -v
```

!!! tip
    Put the cache-configuration step **first**, before `checkout` and any
    `pip install` / `apt-get install`, so every later step benefits from the cache.

---

## FAQ

**Q1: Do I have to use the cache?**

No. It is opt-in and purely a speed/reliability optimization. Without it, your jobs still
work by going to the public mirrors directly.

**Q2: The cache address does not resolve / connection refused.**

- Confirm the commands run **inside** a job on an Ascend NPU runner (within
  `container.image`). The service address is cluster-internal and is not reachable from
  outside the cluster.
- Confirm you used the correct port for the package manager (80 for pip, 8081 for APT,
  8083 for yum/dnf, 8082 for rustup).

**Q3: A package is missing or out of date in the cache.**

The PyPI cache automatically falls back to official `pypi.org` when the upstream mirror
has not synced a freshly published package, so this should be rare. If you still hit a
stale entry, please [open a discussion](https://github.com/ascend-gha-runners/docs/discussions).

**Q4: How do I confirm my repository is counted as "using" the cache?**

See the [Integrated Repositories](Repo.md) page — it runs a daily audit and shows whether
the PyPI and APT caches are in use for each integrated repository.

---

## Feedback & Support

If you encounter any issues configuring or using the cache, please
[create a discussion](https://github.com/ascend-gha-runners/docs/discussions).

When submitting, please provide:

- Project name and Git repository URL
- Which package manager and which command failed
- The error message and, if possible, the relevant `X-*-Cache` response header
