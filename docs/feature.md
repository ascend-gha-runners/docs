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
    RUSTUP_DIST_SERVER: http://cache-service.nginx-pypi-cache.svc.cluster.local:8082
    RUSTUP_UPDATE_ROOT: http://cache-service.nginx-pypi-cache.svc.cluster.local:8082/rustup
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

### Summary

| Cache Type | Port | Upstream | Client |
| :--- | :---: | :--- | :--- |
| PyPI | 80 | repo.huaweicloud.com + pypi.org fallback | pip / uv |
| APT | 8081 | ports/archive.ubuntu.com | apt-get |
| Rust | 8082 | mirrors.huaweicloud.com/rustup | rustup |
| YUM | 8083 | repo.huaweicloud.com/openeuler | dnf / yum |
