# Platform Features

## Cache Service

To reduce bandwidth pressure and speed up CI builds, we deploy an in-cluster nginx cache service that proxies common package registries. All runner pods can access it via the internal service address.

**Service address:** `cache-service.nginx-pypi-cache.svc.cluster.local`

---

### PyPI Cache (Port 80)

Proxies Python package index. Falls back to `pypi.org` when the upstream mirror returns 404.

**Configure in your workflow:**

```yaml
- name: Configure pip cache
  run: |
    pip config set global.index-url http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
    pip config set global.trusted-host cache-service.nginx-pypi-cache.svc.cluster.local
```

**Or via environment variable:**

```yaml
env:
  PIP_INDEX_URL: http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
  PIP_TRUSTED_HOST: cache-service.nginx-pypi-cache.svc.cluster.local
```

**PyTorch wheels** are also cached. Use the `/whl` path:

```yaml
- name: Install PyTorch via cache
  run: |
    pip install torch --index-url http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/cpu
```

---

### APT Cache (Port 8081)

Proxies Ubuntu/Debian package repositories (`ports.ubuntu.com`, `archive.ubuntu.com`).

**Configure in your workflow:**

```yaml
- name: Configure apt cache
  run: |
    sed -Ei 's@(ports|archive).ubuntu.com@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' /etc/apt/sources.list
```

---

### Rust / rustup Cache (Port 8082)

Proxies `mirrors.huaweicloud.com/rustup` for Rust toolchain downloads.

**Configure in your workflow:**

```yaml
- name: Configure rustup cache
  env:
    RUSTUP_DIST_SERVER: http://cache-service.nginx-pypi-cache.svc.cluster.local:8082/rustup
    RUSTUP_UPDATE_ROOT: http://cache-service.nginx-pypi-cache.svc.cluster.local:8082/rustup/rustup
  run: |
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
```

---

### YUM / DNF Cache (Port 8083)

Proxies `repo.huaweicloud.com/openeuler` for openEuler RPM packages.

**Configure in your workflow:**

```yaml
- name: Configure yum cache
  run: |
    sed -i 's|https://repo.openeuler.org|http://cache-service.nginx-pypi-cache.svc.cluster.local:8083|g' /etc/yum.repos.d/*.repo
```

---

### crates.io Cache (Port 8085)

Proxies the crates.io sparse index for Rust crate dependencies.

**Configure in your workflow:**

```yaml
- name: Configure cargo cache
  env:
    CRATES_IO_INDEX: http://cache-service.nginx-pypi-cache.svc.cluster.local:8085/index/
  run: |
    mkdir -p $HOME/.cargo
    cat > $HOME/.cargo/config.toml <<EOF
    [source.crates-io]
    replace-with = "huaweicloud"

    [source.huaweicloud]
    registry = "sparse+http://cache-service.nginx-pypi-cache.svc.cluster.local:8085/index/"
    EOF
```

---

### Squid Proxy (Port 3128)

A general-purpose outbound HTTP(S) forward proxy and cache (`squid-cache.squid.svc.cluster.local:3128`).
Unlike the registry-specific caches above, it caches arbitrary external HTTP responses.

---

### BuildKit Cache

In-cluster BuildKit (`buildkitd-{arch}:1234`) caches image build layers. Because the local cache is
ephemeral, the durable cache is kept in the registry via `cache-from`/`cache-to` (or
`--import-cache`/`--export-cache`), stored as a `buildcache`/`buildkit-cache` tag.

---

### runs-on/cache (S3-backed)

Self-hosted runners cannot use the GitHub-hosted Actions cache. Use the runs-on cache actions instead
(`runs-on/cache@v5`, `runs-on/cache/restore@v5`, `runs-on/cache/save@v5`), backed by S3 object storage.

---

### Summary

| Cache Type | Port | Upstream | Client |
| :--- | :---: | :--- | :--- |
| PyPI | 80 | repo.huaweicloud.com + pypi.org fallback | pip / uv |
| APT | 8081 | ports/archive.ubuntu.com | apt-get |
| Rust | 8082 | mirrors.huaweicloud.com/rustup | rustup |
| YUM | 8083 | repo.huaweicloud.com/openeuler | dnf / yum |
| crates.io | 8085 | crates.io sparse index | cargo |
| Squid proxy | 3128 | general outbound HTTP(S) | http_proxy / HTTPS_PROXY |
| BuildKit | — | image registry (`buildcache` / `buildkit-cache` tag) | buildctl / buildx |
| runs-on cache | — | S3 object storage | runs-on/cache@v5 |
