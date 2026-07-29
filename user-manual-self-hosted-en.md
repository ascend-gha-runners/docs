# BuildKit Self-Hosted Image Build Solution (DEG Review Doc)

## 0. Solution Overview

### 0.1 Background & Pain Points

We replaced Docker `buildx` with BuildKit's `buildctl` in self-hosted GitHub Actions Runners (ARC on K8s) for CI image builds of AI projects including vllm-ascend, vllm-omni, and vllm-vime. The following issues were encountered:

| # | Pain Point | Root Cause | Impact |
|---|------------|------------|--------|
| 1 | OOM during concurrent builds | `replicaCount: 1`, no parallelism limit | Queued builds, frequent memory exhaustion |
| 2 | Cache lost on restart | `emptyDir` backing store | Full rebuilds (10-30 min) after every Pod restart |
| 3 | Uncontrolled disk growth | Loose GC policy (48h retention), not in config file | Disk fills up over time |
| 4 | Slow builds & pushes | No registry cache, buildctl/server version mismatch | Unpredictable CI duration |
| 5 | Network instability | Squid proxy latency affects pull speed | Occasional build failures |
| 6 | No shared cache | Build cache directory is ephemeral | Cannot share across replicas |

### 0.2 Design Goals

| Goal | Target |
|------|--------|
| **High Concurrency** | Support 24 concurrent AI image build steps |
| **Persistent Cache** | Cache survives Pod restarts; shared across replicas |
| **Memory Safety** | Single AI image (20GB+ layers) builds never trigger OOM |
| **Automatic GC** | 24h keep window + 100GB cap; auto-purge unreferenced cache |
| **CI Integration** | buildctl v0.31.1 aligned with server; `--export-cache` / `--import-cache` support |

### 0.3 Architecture

```
┌─────────────────────────┐
│   GitHub Workflow       │
│   runs-on: [label, gy]  │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────────────────────────────┐
│  ARC Runner Pod (postStart auto-installs buildctl)│
│  BUILDKITD_ADDR=tcp://buildkitd-xxx-service:1234 │
│  Vault injects TLS certs + Docker config          │
└───────────┬─────────────────────────────────────┘
            │ buildctl (TLS)
            ▼
┌─────────────────────────────────────────────────┐
│  BuildKit Server Deployment                      │
│  ┌───────────────────────────────────────────┐  │
│  │ replicaCount: 6                           │  │
│  │ max-parallelism: 4 per Pod                │  │
│  │ resources: 32cpu / 64Gi                   │  │
│  │ snapshotter: fuse-overlayfs               │  │
│  │ ┌─────────────┐  ┌─────────────────────┐  │  │
│  │ │ /etc/buildkit│  │ /home/user/.local/  │  │  │
│  │ │ buildkitd    │  │ share/buildkit      │  │  │
│  │ │ .toml (CM)   │  │ (PVC via SFS Turbo) │  │  │
│  │ └─────────────┘  └─────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└───────────┬─────────────────────────────────────┘
            │ push
            ▼
┌─────────────────────────────────────────────────┐
│  SWR / Docker Hub Registry                      │
│  (--import-cache / --export-cache)              │
└─────────────────────────────────────────────────┘
```

---

## 1. Design Details

### 1.1 Persistent Cache: emptyDir → PVC

**Problem**: `persistence.enabled: false` caused the buildkit data directory to use `emptyDir`, losing all cache on Pod restart.

**Solution**: Enable SFS Turbo ReadWriteMany PVC with separate paths for amd64 and arm64.

| Item | Value |
|------|-------|
| Storage Type | `csi-sfsturbo` (Huawei SFS Turbo) |
| Access Mode | `ReadWriteMany` |
| Capacity | 1228Gi |
| amd64 Path | `/buildkitd-cache-amd64` |
| arm64 Path | `/buildkitd-cache-arm64` |
| Multi-replica Sharing | 6 replicas can read/write the same PVC |

**Chart Change**: PVC name changed from hardcoded `buildkitd-cache` to `{appName}-cache` to avoid collisions in the same namespace (e.g., `buildkitd-amd64-cache` vs `buildkitd-arm64-cache`).

### 1.2 Concurrency Control: Multi-Replica + max-parallelism

**Problem**: AI images (CANN, Ascend Toolkit, etc.) have base layers of 15-30GB. A single instance with unlimited parallelism easily hits OOM.

**Solution**: `replicaCount: 6` + `max-parallelism: 4`.

```
6 replicas × 4 parallel steps = 24 concurrent build steps
```

> **Key insight**:

```
One buildctl build (one Dockerfile)
          │
          ▼
     ┌─────────────────────────────────────────┐
     │         Single buildkitd Replica         │
     │  max-parallelism: 4 slots                │
     │  ┌────┐ ┌────┐ ┌────┐ ┌────┐           │
     │  │ S1 │ │ S2 │ │ S3 │ │ S4 │           │
     │  └────┘ └────┘ └────┘ └────┘           │
     │    ↑      ↑      ↑      ↑              │
     │  stage1 stage2 stage3 stage4 (if any)    │
     │                                         │
     │  One replica = One Dockerfile = One build│
     └─────────────────────────────────────────┘

Multiple projects pushing simultaneously
          │
     ┌─────┼─────┬─────┬─────┬─────┐
     ▼     ▼     ▼     ▼     ▼     ▼
 ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐
 │ R1 │ │ R2 │ │ R3 │ │ R4 │ │ R5 │ │ R6 │    ← 6 replicas, each handles one project
 └────┘ └────┘ └────┘ └────┘ └────┘ └────┘
   ProjA  ProjB  ProjC  ProjD  ProjE  ProjF
```

| Concept | Meaning |
|---------|---------|
| One replica | Handles **one** `buildctl build` request (one Dockerfile) at a time |
| `max-parallelism: 4` | At most **4 independent stages** run concurrently within that Dockerfile |
| `replicaCount: 6` | At most **6 different projects** can build concurrently |
| Between replicas | Independent; no resource sharing |

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `replicaCount` | 4 | 6 replicas per architecture |
| `max-parallelism` | 4 | Max 4 parallel steps per replica (20GB+ layers, 4 steps ≈ 60-80GB memory) |
| `podAntiAffinity` | `requiredDuringScheduling` | Spread replicas across physical nodes |
| `resources.requests.memory` | 64Gi | Memory is incompressible; requests=limits prevents OOM Kill |
| `resources.requests.cpu` | 16 | CPU is compressible; requests < limits allows Burst |
| `resources.limits.cpu` | 32 | Peak CPU availability |

### 1.3 GC Policy: buildkitd.toml Single Policy

**Problem**: The old approach used CLI flags (`--oci-worker-gc` / `--oci-worker-gc-keepstorage`) with a triplet format that cannot express `keepDuration` and `reservedSpace`. The previously attempted second GC policy (`unused=true` / `maxUnused=...`) was not a valid BuildKit TOML key and was silently ignored.

**Solution**: Generate `buildkitd.toml` via a ConfigMap template, mounted at `/etc/buildkit/buildkitd.toml`, loaded at startup via `--config`.

**Values Configuration**:
```yaml
config:
  maxParallelism: 4
  gcPolicies:
    - keepDuration: 24h
      keepBytes: 50GB
      maxUsedSpace: "100GB"
```

**Rendered buildkitd.toml**:
```toml
[worker.oci]
  enabled = true
  gc = true
  max-parallelism = 4
  [[worker.oci.gcpolicy]]
    keepDuration = "24h"
    reservedSpace = "50GB"
    maxUsedSpace = "100GB"
  snapshotter = "fuse-overlayfs"
```

**How GC Works**:

```
New builds (< 24h)      > 24h, under 100GB        > 24h, over 100GB
     │                        │                          │
     ▼                        ▼                          ▼
┌──────────┐  keep   ┌──────────────┐  start    ┌──────────────────┐
│ Active    │ ──────►│ Still kept   │ ────────► │ Delete oldest     │
│ protected │         │ (under cap)  │            │ (skip InUse)     │
└──────────┘         └──────────────┘            └──────────────────┘
```

**Why a single policy is sufficient**:
- BuildKit's internal GC engine auto-skips `InUse=true` records (`cache/manager.go:1148`), so active cache is never deleted by mistake
- One policy with `keepDuration: 24h` + `reservedSpace: 50GB` + `maxUsedSpace: 100GB` covers all scenarios
- 100GB limit provides ample headroom on a 1.2TB PVC

### 1.4 Snapshotter: fuse-overlayfs

BuildKit supports three snapshotters for managing container image layer storage:

| Snapshotter | Mechanism | Requires Privilege | Rootless | Performance |
|-------------|-----------|-------------------|----------|-------------|
| **native** | Direct FS ops, depends on kernel overlayfs | No | No | Best |
| **overlayfs** | Kernel overlay filesystem | No | No (needs user ns remap) | Best |
| **fuse-overlayfs** | Userspace FUSE overlayfs | `/dev/fuse` | Yes | 15-20% slower |

**Why fuse-overlayfs is required**:

We run in **rootless mode** (`--oci-worker-no-process-sandbox`), buildkitd with `uid=1000`. Under rootless:
- `overlayfs` / `native` require `user.max_user_namespaces` and VFS kernel capabilities, difficult to configure reliably on K8s nodes
- `fuse-overlayfs` operates in userspace, only requires `/dev/fuse`

**Dependency chain**:

```
buildkitd Pod                           K8s Node
┌──────────────────────┐              ┌──────────────────────┐
│ resources:           │   request   │ generic-device-plugin│
│   devic.es/fuse: 1   │─────────────►│ "fuse": count=10     │
│                      │              │ path: /dev/fuse      │
│ container:           │   mount     │                      │
│   /dev/fuse ←────────│──────────────│ host /dev/fuse       │
│                      │              │                      │
│ buildkitd ──► fuse-  │              │                      │
│              overlayfs              │                      │
└──────────────────────┘              └──────────────────────┘
```

**Performance**:
- fuse-overlayfs is ~15-20% slower than kernel overlayfs (FUSE user-kernel context switching)
- For AI image builds (IO-bound rather than CPU-bound), the overhead is acceptable
- The key benefit is rootless security isolation without privileged containers

> **Prerequisite**: The cluster must have the `generic-device-plugin` DaemonSet (see `manifests/generic-device-plugin/`) to expose `/dev/fuse` via the K8s Device Plugin.

### 1.5 Build Acceleration: Registry Cache

**Solution**: Add `--export-cache` and `--import-cache` in CI workflows to store build cache in the image registry:

```bash
buildctl build \
  --frontend dockerfile.v0 \
  --local context=. \
  --import-cache type=registry,ref=swr.cn-southwest-2.myhuaweicloud.com/myorg/myimage:buildcache \
  --export-cache type=registry,ref=swr.cn-southwest-2.myhuaweicloud.com/myorg/myimage:buildcache,mode=max \
  --output type=image,name=swr.cn-southwest-2.myhuaweicloud.com/myorg/myimage:v1.0,push=true
```

**Expected Performance**:
- First build: full rebuild (10-30 min, depending on image size)
- Cache hit: changed layers only (30-120 seconds)

### 1.6 buildctl Version Alignment

Runner ConfigMap `BUILDKIT_VERSION` upgraded from `v0.29.0` to `v0.31.1` to match the server image version and avoid protocol incompatibility.

### 1.7 Component Mapping

```
Values (values-guiyang-006-amd64.yaml)
     │
     ├── config.maxParallelism ──► configmap.yaml ──► max-parallelism = 4
     ├── config.gcPolicies     ──► configmap.yaml ──► [[worker.oci.gcpolicy]]
     ├── persistence.enabled   ──► deployment.yaml ─► PVC / emptyDir
     ├── args                  ──► deployment.yaml ─► CLI args
     ├── replicaCount          ──► deployment.yaml ─► spec.replicas
     └── resources             ──► deployment.yaml ─► container.resources
```

---

## 2. Key Concepts

### 2.1 Runner Labels

Two-label combination:

```yaml
runs-on:
  - linux-amd64-cpu-4-buildkit      # Runner type (CPU spec + buildkit flag)
  - gy-006                           # Cluster location
```

| Label | Meaning | Purpose |
|-------|---------|---------|
| `linux-amd64-cpu-4-buildkit` | Linux x86_64, 4 cores, with buildkit | Select runner type |
| `gy-006` | Deployed in Guiyang-006 cluster | Select cluster |

**Available combinations**:
- `[linux-amd64-cpu-4-buildkit, gy-006]` — x86_64, 4 cores, Guiyang
- `[linux-aarch64-cpu-4-buildkit, gy-006]` — ARM64, 4 cores, Guiyang

### 2.2 BuildKit Server Address

Auto-configured by Runner:
```
BUILDKITD_ADDR=tcp://buildkitd-amd64-service.buildkitd:1234
```

---

## 3. Resource Specs

| Runner Label | Arch | CPU | Memory | Cluster | BuildKit Server |
|-------------|------|-----|--------|---------|-----------------|
| `linux-amd64-cpu-4-buildkit` | amd64 | 4 cores | 8GB | gy-006 | `buildkitd-amd64-service` |
| `linux-aarch64-cpu-4-buildkit` | arm64 | 4 cores | 8GB | gy-006 | `buildkitd-arm64-service` |

> **Server config**: 32cpu / 64Gi per replica, 6 replicas per architecture, `max-parallelism: 4`.

---

## 4. User Guide

### 4.1 Specifying Runner Labels

```yaml
jobs:
  build:
    runs-on: [linux-amd64-cpu-4-buildkit, gy-006]
    steps:
      - uses: actions/checkout@v3
      - name: Build image
        run: |
          buildctl build \
            --frontend dockerfile.v0 \
            --local context=. \
            --output type=image,name=docker.io/myorg/myimage:v1.0,push=true
```

### 4.2 Common Build Scenarios

**Basic build**:
```bash
buildctl build \
  --frontend dockerfile.v0 \
  --local context=. \
  --local dockerfile=. \
  --output type=image,name=docker.io/myorg/myimage:v1.0,push=true
```

**Multi-arch build**:
```bash
buildctl build \
  --frontend dockerfile.v0 \
  --local context=. \
  --platform linux/amd64,linux/arm64 \
  --output type=image,name=docker.io/myorg/myimage:v1.0,push=true
```

**With registry cache** (recommended):
```bash
buildctl build \
  --frontend dockerfile.v0 \
  --local context=. \
  --import-cache type=registry,ref=swr.cn-southwest-2.myhuaweicloud.com/myorg/myimage:buildcache \
  --export-cache type=registry,ref=swr.cn-southwest-2.myhuaweicloud.com/myorg/myimage:buildcache,mode=max \
  --output type=image,name=swr.cn-southwest-2.myhuaweicloud.com/myorg/myimage:v1.0,push=true
```

**Using registry credentials**:
```yaml
env:
  BUILDKIT_REGISTRY_CREDS_DOCKER_IO: ${{ secrets.DOCKER_USERNAME }}:${{ secrets.DOCKER_TOKEN }}
```

> Hostname naming: `docker.io` → `DOCKER_IO`, `ghcr.io` → `GHCR_IO` (underscore + uppercase).

### 4.3 Complete CI Example

```yaml
name: Build and Push Image

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]

jobs:
  build:
    runs-on: [linux-amd64-cpu-4-buildkit, gy-006]
    steps:
      - uses: actions/checkout@v3
      - name: Prepare metadata
        id: meta
        run: |
          TAG="${GITHUB_REF#refs/tags/}"
          [ "$TAG" = "$GITHUB_REF" ] && TAG="${GITHUB_REF#refs/heads/}-${{ github.sha }}"
          echo "tag=$TAG" >> $GITHUB_OUTPUT
      - name: Build and push
        env:
          BUILDKIT_REGISTRY_CREDS_DOCKER_IO: ${{ secrets.DOCKER_USERNAME }}:${{ secrets.DOCKER_TOKEN }}
        run: |
          buildctl build \
            --frontend dockerfile.v0 \
            --local context=. \
            --import-cache type=registry,ref=docker.io/myorg/myimage:buildcache \
            --export-cache type=registry,ref=docker.io/myorg/myimage:buildcache,mode=max \
            --output type=image,name=docker.io/myorg/myimage:${{ steps.meta.outputs.tag }},push=true
```

---

## 5. Ops Configuration Reference

### 5.1 Persistent Cache

**File**: `argocd/clusters/buildkit-server/values-guiyang-006-amd64.yaml`

```yaml
buildkitd:
  persistence:
    enabled: true
    accessMode: ReadWriteMany
    storageClass: "csi-sfsturbo"
    size: 1228Gi
    path: "/buildkitd-cache-amd64"
    sfsturboShareId: "01d769be-700b-4f8d-bf4f-54899db213e6"
```

PVC name auto-derived as `{appName}-cache` (e.g., `buildkitd-amd64-cache`, `buildkitd-arm64-cache`).

### 5.2 GC Policy

**Values**:
```yaml
config:
  maxParallelism: 4
  gcPolicies:
    - keepDuration: 24h
      keepBytes: 50GB
      maxUsedSpace: "100GB"
```

**Rendered buildkitd.toml**:
```toml
[worker.oci]
  enabled = true
  gc = true
  max-parallelism = 4
  [[worker.oci.gcpolicy]]
    keepDuration = "24h"
    reservedSpace = "50GB"
    maxUsedSpace = "100GB"
  snapshotter = "fuse-overlayfs"
```

| Parameter | TOML Key | Meaning | Value |
|-----------|----------|---------|-------|
| `maxParallelism` | `max-parallelism` | Max parallel build steps | `4` |
| `keepDuration` | `keepDuration` | Min cache retention time | `24h` |
| `keepBytes` | `reservedSpace` | Minimum reserved space | `50GB` |
| `maxUsedSpace` | `maxUsedSpace` | Max cache space | `100GB` |

### 5.3 Concurrency & Resources

```yaml
buildkitd:
  replicaCount: 6
  config:
    maxParallelism: 4
  resources:
    limits:
      cpu: 32
      memory: 64Gi
    requests:
      cpu: 16
      memory: 64Gi
```

**Capacity**: 6 replicas × 4 parallel = 24 concurrent build steps. `podAntiAffinity` ensures distribution across physical nodes.

### 5.4 Network Proxy

```yaml
env:
  - name: HTTP_PROXY
    value: "http://squid-cache.squid.svc.cluster.local:3128"
  - name: NO_PROXY
    value: "localhost,127.0.0.1,.svc.cluster.local,.cluster.local"
```

Pull traffic goes through Squid caching proxy; intra-cluster traffic is direct.

---

## 6. Deployed Files

| File | Purpose | Changes |
|------|---------|---------|
| `argocd/clusters/buildkit-server/values-guiyang-006-amd64.yaml` | amd64 cluster values | `persistence: true`, 6 replicas, single GC policy |
| `argocd/clusters/buildkit-server/values-guiyang-006-arm64.yaml` | arm64 cluster values | Synced with amd64 |
| `manifests/buildkitd-server/chart/templates/configmap.yaml` | Generates buildkitd.toml | **New** |
| `manifests/buildkitd-server/chart/templates/deployment.yaml` | Deployment template | Appended `--config`, parameterized PVC name |
| `manifests/buildkitd-server/chart/templates/pvc.yaml` | PVC template | Parameterized PVC name |
| `other/.../linux-amd64-cpu-4-buildkit-configmap.yaml` | Runner PodTemplate | buildctl `v0.29.0` → `v0.31.1` |
| `other/.../linux-aarch64-cpu-4-buildkit-configmap.yaml` | Runner PodTemplate | Same as above |
| `docs/user-manual-self-hosted-zh.md` | Design review doc (CN) | This file |
| `docs/user-manual-self-hosted-en.md` | Design review doc (EN) | New |

---

## 7. Troubleshooting

### Job stuck at "Waiting for..."

Verify labels:
```yaml
# ✅ Correct
runs-on: [linux-amd64-cpu-4-buildkit, gy-006]
# ❌ Missing cluster label
runs-on: linux-amd64-cpu-4-buildkit
```

### buildctl: command not found

Runner Pod `postStart` hook auto-downloads buildctl to PVC cache:
```bash
ls -lh /root/.cache/buildkit/bin/amd64/buildctl
```

### Slow builds / no cache hits

Check `--import-cache` and `--export-cache` in CI commands. Check PVC status:
```bash
kubectl get pvc -n buildkitd
kubectl describe pvc buildkitd-amd64-cache -n buildkitd
```

### Disk full

```bash
# Manual GC
buildctl prune --all

# Expand PVC (update values)
persistence:
  size: 2048Gi
```

---

## 8. Quick Reference

```bash
# Build & push
buildctl build \
  --frontend dockerfile.v0 --local context=. \
  --output type=image,name=myimage:v1.0,push=true

# Multi-arch
buildctl build \
  --frontend dockerfile.v0 --local context=. \
  --platform linux/amd64,linux/arm64 \
  --output type=image,name=myimage:v1.0,push=true

# With registry cache
buildctl build \
  --frontend dockerfile.v0 --local context=. \
  --import-cache type=registry,ref=myimage:buildcache \
  --export-cache type=registry,ref=myimage:buildcache,mode=max \
  --output type=image,name=myimage:v1.0,push=true

# Ops
buildctl du                    # Cache usage
buildctl prune --all           # Purge all cache
buildctl debug workers         # List workers
```

### docker build → buildctl

| Operation | `docker build` | `buildctl` |
|-----------|----------------|------------|
| Build | `docker build -t img .` | `buildctl build --output type=image,name=img` |
| Push | `docker push img` | `--output type=image,name=img,push=true` |
| Multi-arch | Requires `buildx` | Native `--platform` |
| Cache | Automatic | `--import-cache` / `--export-cache` |
| Prune | `docker prune` | `buildctl prune` |

---

## 9. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| SFS Turbo performance jitter | IO contention with multi-replica shared PVC | `max-parallelism: 4` limits concurrent IO; monitor PVC IOPS |
| Insufficient node resources | 6 replicas × 64Gi fails to schedule | CPU requests=16 allows Burst headroom; verify node capacity |
| PVC full prevents builds | Image push failures | 100GB GC cap + 1.2TB SFS Turbo; manual `buildctl prune` if needed |
| buildkitd.toml format errors | buildkitd fails to start | Helm `--dry-run` validation; canary deployment |

---

## 10. Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | 2026-07-22 | DEG review version: Added solution overview, design decisions, risk analysis; PVC enabled; 6 replicas + max-parallelism=4; buildkitd.toml GC; buildctl v0.31.1 |
| 1.0 | 2026-07-21 | Initial version: User manual for ARC Runner + BuildKit Server architecture |
