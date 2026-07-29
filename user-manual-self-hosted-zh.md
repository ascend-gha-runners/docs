# BuildKit 自托管镜像构建方案（DEG 评审文档）

## 0. 方案概述

### 0.1 背景与痛点

在自托管 GitHub Actions Runner（ARC on K8s）中，K8s 容器内无法运行 Docker daemon（DinD 需特权），无法使用 `docker build`。我们用 BuildKit 的 `buildctl` 直接与 K8s 中的 BuildKit Server 通信，替代 Docker 进行 CI 镜像构建。

| # | 痛点 | 根因 | 解决方案 |
|---|------|------|---------|
| 1 | 容器内无法运行 Docker | K8s pod 无特权模式 | BuildKit rootless + `buildctl` TCP |
| 2 | 并发构建 OOM | 单实例无并行限制 | 多副本 + `max-parallelism` GC 策略 |
| 3 | 缓存丢失 | Pod 重启后 `emptyDir` 清空 | 仅靠 registry cache 恢复，SFS Turbo 与 rootless 不兼容 |
| 4 | Remote Cache 导出慢 | `mode=max` 导出 10-15GB 中间层 | `type=inline`，嵌入镜像 manifest |
| 5 | pip install hash 冲突 | `--extra-index-url` 污染依赖索引 | `--find-links` + 统一 pypi-cache 代理 |
| 6 | 网络访问受限 | 集群内无公网出口 | Squid 代理 + nginx-pypi-cache |

### 0.2 设计目标

| 目标 | 指标 |
|------|------|
| **高并发** | 支持 8 个 Dockerfile × 2 架构 = 16 个并行 CI 构建 |
| **快速验证** | 单 Dockerfile CI 构建 5-15 分钟（含 git clone + pip install + 编译） |
| **全架构覆盖** | amd64 + arm64 各独立 buildkitd 服务 |
| **离线友好** | 所有外部依赖通过集群内代理/cache，无需公网 |

### 0.3 架构总览

```
┌──────────────────────────────────────────────────────────────┐
│                     GitHub Workflow                          │
│   strategy.matrix: 8 Dockerfiles × {amd64, arm64} = 16 jobs │
│   runs-on: [linux-{arch}-cpu-4-buildkit, gy-006]            │
└───────────┬──────────────────────────────────────────────────┘
            │ buildctl --addr tcp://buildkitd-{arch}-service:1234
            ▼
┌──────────────────────────────────────────────────────────────┐
│  K8s Cluster (buildkitd namespace)                           │
│                                                              │
│  ┌─ buildkitd-amd64-service (ClusterIP :1234) ────────────┐ │
│  │  replicaCount: 3, nodeSelector: kubernetes.io/arch=amd64│ │
│  │  max-parallelism: 4, 32cpu/64Gi per pod                │ │
│  │  snapshotter: fuse-overlayfs (via generic-device-plugin)│ │
│  │  TLS: mTLS, certs injected by Vault                    │ │
│  │  cache: emptyDir (/home/user/.local/share/buildkit)    │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─ buildkitd-arm64-service (ClusterIP :1234) ────────────┐ │
│  │  replicaCount: 3, nodeSelector: kubernetes.io/arch=arm64│ │
│  │  (同上配置)                                              │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  出口通路: Squid proxy → 外部                                 │
│  pypi cache: nginx-pypi-cache → repo.huaweicloud.com        │
│  apt mirror: nginx-pypi-cache → apt source                  │
│  git proxy: gh-proxy.test.osinfra.cn → github.com           │
└───────────┬──────────────────────────────────────────────────┘
            │ --output type=image,push=true
            │ --export-cache type=inline
            ▼
┌──────────────────────────────────────────────────────────────┐
│  SWR 镜像仓库                                                │
│  swr.cn-southwest-2.myhuaweicloud.com/modelfoundry/         │
│  test-buildkit:{dockerfile}-{arch}-{sha}  (CI 验证镜像)      │
│  buildkit-cache:{dockerfile}-{arch}        (缓存标记镜像)     │
└──────────────────────────────────────────────────────────────┘
```

---

## 1. 设计方案

### 1.1 完整 CI 示例（8 Dockerfile × 2 架构 = 16 构建）

以下是实际运行中的 CI 配置，覆盖 8 个单阶段 Dockerfile，按 3 个 GitHub Workflow 分组：

**Group1**（Dockerfile / Dockerfile.310p / Dockerfile.310p.openEuler）— 910b + 310p 系列
**Group2**（Dockerfile.a3 / Dockerfile.a3.openEuler / Dockerfile.openEuler）— a3 系列
**Group3**（Dockerfile.a5 / Dockerfile.a5.openEuler）— a5 系列

```yaml
name: buildkit-dockerfile-test-group1

on:
  pull_request:
    paths:
      - '.github/workflows/buildkit-dockerfile-test-group1.yaml'
      - 'Dockerfile'
      - 'Dockerfile.310p'
      - 'Dockerfile.310p.openEuler'

jobs:
  build-test:
    name: "${{ matrix.dockerfile }} (${{ matrix.runner_info.arch }})"
    runs-on: ${{ matrix.runner_info.runner }}
    container:
      image: swr.cn-southwest-2.myhuaweicloud.com/base_image/ascend-ci/cann:9.0.0-a3-ubuntu22.04-py3.12

    strategy:
      fail-fast: false
      matrix:
        dockerfile:
          - Dockerfile
          - Dockerfile.310p
          - Dockerfile.310p.openEuler
        runner_info:
          - {runner: linux-aarch64-cpu-4-buildkit-gy006, arch: arm64}
          - {runner: linux-amd64-cpu-4-buildkit-gy006, arch: amd64}

    steps:
      - uses: actions/checkout@v7

      - name: Build image with buildctl
        run: |
          buildctl \
            --addr="${BUILDKITD_ADDR}" \
            --tlscacert="${DOCKER_CONFIG}/ca.pem" \
            --tlscert="${DOCKER_CONFIG}/cert.pem" \
            --tlskey="${DOCKER_CONFIG}/key.pem" \
            build \
            --progress=plain \
            --frontend dockerfile.v0 \
            --local context=. \
            --local dockerfile=. \
            --opt filename=${{ matrix.dockerfile }} \
            --opt build-arg:APTMIRROR=http://cache-service.nginx-pypi-cache.svc.cluster.local:8081 \
            --opt build-arg:PIP_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple \
            --opt build-arg:SOC_VERSION=${{ steps.vars.outputs.soc_version }} \
            --opt build-arg:COMPILE_CUSTOM_KERNELS=0 \
            --secret id=dockerconfig,src=/home/user/.docker/config.json \
            --import-cache type=registry,ref=swr.cn-southwest-2.myhuaweicloud.com/modelfoundry/buildkit-cache:${{ matrix.dockerfile }}-${{ matrix.runner_info.arch }} \
            --export-cache type=inline \
            --output type=image,"name=swr.cn-southwest-2.myhuaweicloud.com/modelfoundry/test-buildkit:${{ matrix.dockerfile }}-${{ matrix.runner_info.arch }}-${{ github.sha }},name=swr.cn-southwest-2.myhuaweicloud.com/modelfoundry/buildkit-cache:${{ matrix.dockerfile }}-${{ matrix.runner_info.arch }}",push=true
```

**关键参数说明**：

| 参数 | 作用 |
|------|------|
| `--addr` | buildkitd 服务器地址（Runner `postStart` 注入 `BUILDKITD_ADDR` 环境变量） |
| `--tlscacert/--tlscert/--tlskey` | mTLS 证书（Vault 注入到 `/certs/`） |
| `--opt build-arg:APTMIRROR` | 将 apt 源替换为集群内 nginx-pypi-cache |
| `--opt build-arg:PIP_INDEX_URL` | pip index 指向集群内 pypi cache |
| `--secret id=dockerconfig` | SWR 镜像仓库凭证，用于 pull 基础镜像和 push |
| `--import-cache type=registry` | 从上次推送的镜像读取 inline 缓存 |
| `--export-cache type=inline` | 将构建缓存嵌入镜像 manifest（不在单独推送） |
| `--output type=image,name=...` | **双 tag** 推送：CI 验证镜像 + 缓存标记镜像 |

### 1.2 并发控制：多副本 + max-parallelism

`max-parallelism` 是**副本内局部限制**，非集群共享。每个 `buildctl build` 请求绑定到一个副本（通过 Service 随机分配），该构建的所有步骤都在这个副本上执行，不会跨副本分发。

```
Pod-1 (max-parallelism: 4，副本内独立调度器)
  ├── build A 的步骤-1 ████████ (占 1 槽)
  ├── build A 的步骤-2    ████████ (占 1 槽)
  ├── build B 的步骤-1 ████████ (占 1 槽)
  └── build C 的步骤-1 ████████ (占 1 槽，4 槽全满)

  build C 的步骤-2 ──── 排队等待任意步骤结束 → 不跨副本
  build D ────────── 排队等待（等有槽位才开始）

Pod-2 (max-parallelism: 4，独立的调度器)
  └── build E 的步骤-1 ████████ (独立调度，与 Pod-1 无关)
```

**与多阶段 Dockerfile 的关系**：

| Dockerfile 类型 | 并行步骤数 | 一个副本能同时跑几个 build |
|----------------|-----------|------------------------|
| 单阶段（我们的场景） | 1-3 个并行步骤 | 2-4 个（取决于各 build 的步骤数） |
| 多阶段 (multi-stage) | 3-8 个并行步骤 | 1-2 个 |

我们的 8 个 Dockerfile 都是单阶段，每个只占用少量槽位，同一副本可并发处理多个。实际瓶颈是内存（64Gi）而非槽位数。

### 1.3 Dockerfile 设计规范

所有 8 个 Dockerfile 都是**单阶段**构建，结构相同：

```dockerfile
FROM swr.cn-southwest-2.myhuaweicloud.com/base_image/ascend-ci/cann:9.0.1-xxx-py3.12

# 所有外部 URL 通过 ARG → 指向集群内代理
ARG PIP_INDEX_URL="http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple"
ARG ASCEND_INDEX_URL="http://cache-service.nginx-pypi-cache.svc.cluster.local/ascend/repos/pypi"
ARG PYTORCH_INDEX_URL="http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/cpu"

# 1. 系统依赖
RUN apt-get install -y gcc cmake ...   # 通过 APTMIRROR 走集群代理

# 2. Python 依赖
RUN pip config set global.index-url ${PIP_INDEX_URL}
RUN pip install modelscope ray protobuf

# 3. 克隆 vLLM
RUN git clone ${VLLM_REPO} /vllm-workspace/vllm

# 4. 安装 vLLM（不去 PYTORCH_INDEX_URL，避免 jinja2 hash 冲突）
RUN VLLM_TARGET_DEVICE="empty" pip install -e /vllm-workspace/vllm/[audio]

# 5. 安装 vllm-ascend（--find-links 仅找 torch+cpu，不污染依赖）
COPY . /vllm-workspace/vllm-ascend/
RUN pip install -e /vllm-workspace/vllm-ascend/ \
    --find-links ${PYTORCH_INDEX_URL}/torch/ \
    --find-links ${PYTORCH_INDEX_URL}/torchvision/

# 6. triton-ascend（从 ASCEND_INDEX_URL 加载）
RUN pip install triton-ascend==3.2.1 --extra-index-url ${ASCEND_INDEX_URL}
```

| 依赖项 | 来源 | 代理路径 |
|--------|------|---------|
| 基础镜像 (`FROM`) | SWR | 无代理，直接 pull |
| apt 包 | archive.ubuntu.com | `${APTMIRROR}` → nginx-pypi-cache |
| pip 包 | pypi.org | `${PIP_INDEX_URL}` → nginx-pypi-cache |
| torch+cpu wheel | download.pytorch.org | `${PYTORCH_INDEX_URL}` → nginx-pypi-cache |
| triton-ascend wheel | mirrors.huaweicloud.com | `${ASCEND_INDEX_URL}` → nginx-pypi-cache |
| Git 仓库 | github.com | `gh-proxy.test.osinfra.cn` |
| 镜像仓库 (push/pull) | SWR | Squid 代理 |

### 1.4 依赖解析隔离：`--find-links` vs `--extra-index-url`

**问题**：`--extra-index-url ${PYTORCH_INDEX_URL}` 会让 pip 在 `/whl/cpu` 也解析 jinja2、numpy 等间接依赖，nginx sub_filter 把所有下载链接改到 PyTorch R2 CDN → hash 与 PyPI 不同 → 构建失败。

```
    pip 解析 jinja2
    ├── pypi/simple → jinja2-3.1.6 (sha: 68c5548...)  ← PyPI 版本
    └── whl/cpu     → jinja2-3.1.6 (sha: 28425ed...)  ← PyTorch 重新封装的 ×
```

**方案**：vLLM 安装完全不用 `PYTORCH_INDEX_URL`（torch CPU wheel 在 PyPI 上就有）；vllm-ascend 安装用 `--find-links` 替代 `--extra-index-url`：

| 方式 | pip 查找 torch | 解析 jinja2 等间接依赖 | hash 冲突 |
|------|---------------|----------------------|----------|
| `--extra-index-url` | `/whl/cpu` + `/pypi/simple` | 两个索引都搜 | ✗ 可能冲突 |
| `--find-links` | `/whl/cpu/torch/` | 只在 `/pypi/simple` | ✓ 不冲突 |

### 1.5 Registry Cache：inline 替代 mode=max

**原方案**：`--export-cache type=registry,mode=max`，将**所有中间构建层**（~10-15GB）推送到 SWR 作为缓存。

**问题**：`mode=max` 导出数据量大，CI 结束后需等待 1-3 分钟推送缓存。单体 Dockerfile 不存在多阶段构建中间 stage 的缓存需求。

**现方案**：`--export-cache type=inline` + **双 tag 推送**。

```bash
# 旧：两次推送（镜像 + 缓存）
--export-cache type=registry,ref=swr.../buildkit-cache:tag,mode=max
--output type=image,name=swr.../test-buildkit:tag,push=true

# 新：一次推送，双 tag
--export-cache type=inline
--output type=image,"name=swr.../test-buildkit:tag,name=swr.../buildkit-cache:tag",push=true
```

| 对比 | mode=max | type=inline |
|------|----------|-------------|
| 推送次数 | 2 次 | **1 次** |
| 导出耗时 | +1-3 分钟 | **0 额外耗时** |
| 单阶段缓存覆盖 | 100% | 100%（无差异） |
| 多阶段中间 stage 缓存 | ✓ | ✗（不需要） |

### 1.6 GC 策略：buildkitd.toml

```yaml
# values-guiyang-006-amd64.yaml
config:
  maxParallelism: 4
  gcPolicies:
    - keepDuration: 24h
      keepBytes: 50GB
      maxUsedSpace: "100GB"
```

```toml
# 渲染后的 buildkitd.toml
[worker.oci]
  enabled = true
  gc = true
  max-parallelism = 4
  [[worker.oci.gcpolicy]]
    keepDuration = "24h"
    reservedSpace = "50GB"
    maxUsedSpace = "100GB"
```

### 1.7 Snapshotter：fuse-overlayfs

rootless 模式（`uid=1000`）无法使用内核 overlayfs，需 `fuse-overlayfs`。

```
buildkitd Pod                           K8s 节点
┌──────────────────────┐              ┌──────────────────────┐
│ resources:           │   请求       │ generic-device-plugin│
│   devic.es/fuse: 1   │─────────────►│ "fuse": count=10     │
│                      │              │ path: /dev/fuse      │
│ container:           │   挂载       │                      │
│   /dev/fuse ←────────│──────────────│ 宿主机 /dev/fuse     │
└──────────────────────┘              └──────────────────────┘
```

部署前提：集群安装 `generic-device-plugin` DaemonSet（`manifests/generic-device-plugin/`）。

### 1.8 持久化缓存：为什么只能用 emptyDir

当前 gy006 集群使用 `emptyDir`（`persistence.enabled: false`）。

**为什么不能用 SFS Turbo / NFS 作为缓存存储**：

BuildKit 以 **rootless 模式**运行（`uid=1000`），用户层通过 `user_namespaces(7)` 做进程隔离。在构建过程中，buildkitd 需要对缓存文件执行 `chown` 以匹配容器内的 UID/GID 映射。

**NFS（包括华为云 SFS Turbo，底层为 NFS 协议）不支持 user namespace 下的 `chown` 操作**：

```
rootless buildkitd (uid=1000)
  │
  └── user namespace: 1000 ↦ 0 (root in container)
        │
        ├── chown 0:0 /home/user/.local/share/buildkit/...
        │       │
        │       ├── ext4 / xfs (emptyDir)  → ✅ 成功（本地文件系统支持）
        │       └── SFS Turbo (NFS)         → ❌ EINVAL / Operation not permitted
        │
        └── 结果: buildkitd 无法操作 NFS 上的任何文件 → 构建失败
```

| 存储方案 | 文件系统 | `chown` in user ns | 状态 |
|---------|---------|-------------------|------|
| `emptyDir`（节点本地磁盘） | ext4 / xfs | ✅ 支持 | **当前使用** |
| SFS Turbo | NFS | ❌ 不支持 | 不可行 |
| HostPath | ext4 / xfs | ✅ 支持 | 可行，但需固定节点，不推荐 |

emptyDir 的缓存生命周期与 Pod 绑定，Pod 重启即清空。缓解措施：
- **Registry cache**：即便本地缓存丢失，`--import-cache type=registry` 可从上次推送的镜像恢复构建缓存，显著缩减重建时间
- **3 副本分散**：任一 Pod 重启只影响该副本上的构建，其他副本缓存完好
- **GC 策略**：`keepDuration: 24h` + `maxUsedSpace: 100GB` 在 emptyDir 生命周期内保持缓存有效

### 1.9 网络代理

```
集群内 → 集群外（pull 镜像层、apt 源、pip 包）
    ↓
Squid 代理（squid-cache.squid.svc.cluster.local:3128）
    ↓
外部网络（archive.ubuntu.com / pypi.org / github.com）

集群内服务直连（.svc.cluster.local / .cluster.local）
    → NO_PROXY 排除

SwR 镜像仓库 pull/push
    → Squid 代理
```

```yaml
env:
  - name: HTTP_PROXY
    value: "http://squid-cache.squid.svc.cluster.local:3128"
  - name: NO_PROXY
    value: "localhost,127.0.0.1,.svc.cluster.local,.cluster.local"
```

### 1.10 TLS 与凭证管理

buildkitd 使用 mTLS 双向认证，证书通过 HashiCorp Vault Agent Injector 注入：

```
Vault ──► vault-agent-init container ──► /certs/ca.pem
                                          /certs/cert.pem    (server 用)
                                          /certs/key.pem     (server 用)
                                          /home/user/.docker/config.json
```

Runner 通过 `BUILDKITD_ADDR` 环境变量获知 server 地址，通过 `DOCKER_CONFIG` 获取 TLS 证书路径。

### 1.11 组件版本

| 组件 | 版本 | 说明 |
|------|------|------|
| buildkitd image | `moby/buildkit:v0.31.1-rootless` | Server 端，rootless 模式 |
| buildctl (Runner) | `v0.31.1` | Client 端，Runner postStart 自动下载 |
| fuse-overlayfs | 内置 | snapshotter |
| generic-device-plugin | `ghcr.io/squat/generic-device-plugin:0.2.0` | 暴露 /dev/fuse |

---

## 2. 资源规格

| Runner 标签 | 架构 | CPU | 内存 | BuildKit Server |
|-----------|------|-----|------|-----------------|
| `linux-amd64-cpu-4-buildkit-gy006` | amd64 | 4核 | 8GB | `buildkitd-amd64-service.buildkitd:1234` |
| `linux-aarch64-cpu-4-buildkit-gy006` | arm64 | 4核 | 8GB | `buildkitd-arm64-service.buildkitd:1234` |

**Server 端配置**：

| 参数 | 值 |
|------|-----|
| `replicaCount` | 3（每架构） |
| `max-parallelism` | 4 |
| `resources.requests.cpu` | 16 |
| `resources.limits.cpu` | 32 |
| `resources.requests.memory` | 32Gi |
| `resources.limits.memory` | 64Gi |
| `devic.es/fuse` | 1 |
| GC keepDuration | 24h |
| GC maxUsedSpace | 100GB |

---

## 3. 部署文件清单

| 文件 | 作用 |
|------|------|
| `argocd/clusters/buildkit-server/values-guiyang-006-amd64.yaml` | amd64 集群 values（3 副本，fuse-overlayfs） |
| `argocd/clusters/buildkit-server/values-guiyang-006-arm64.yaml` | arm64 集群 values（同上） |
| `manifests/buildkitd-server/chart/templates/configmap.yaml` | 生成 buildkitd.toml ConfigMap |
| `manifests/buildkitd-server/chart/templates/deployment.yaml` | Deployment 模板（TLS + Vault + PVC/emptyDir） |
| `manifests/buildkitd-server/chart/templates/service.yaml` | ClusterIP Service (port 1234) |
| `manifests/buildkitd-server/chart/templates/pvc.yaml` | SFS Turbo PVC 模板 |
| `manifests/generic-device-plugin/` | Device Plugin DaemonSet（暴露 /dev/fuse） |
| CI Workflow（3 个） | GitHub Actions workflow，8 Dockerfile × 2 arch = 16 jobs |

---

## 4. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 节点资源不足 | 3 副本 × 64Gi 无法调度 | CPU requests=16 留 Burst 空间；arm64-only 节点 |
| emptyDir 缓存丢失 | Pod 重启后全量重建 | Registry cache 可恢复构建缓存；3 副本分散，单 Pod 重启影响面小 |
| fuse-overlayfs 性能 | 比内核 overlayfs 慢 15-20% | AI 镜像 IO 密集型可接受 |
| GC 清理活跃缓存 | 理论风险 | BuildKit GC 引擎自动跳过 `InUse=true` 记录 |
| Runner 与 Server 版本不匹配 | 协议不兼容 | `BUILDKIT_VERSION` 统一 `v0.31.1` |
| Squid 代理波动 | 偶发 pull 失败 | `NO_PROXY` 集群内直连；重试机制 |

---

## 4. 并发问题根因分析

### 4.1 问题演进

| 阶段 | 配置 | 现象 | 根因 |
|------|------|------|------|
| v0 | `replicaCount: 1`, 无 `max-parallelism` | 多 CI 任务排队，偶发 OOM Kill | 单副本处理所有请求无全局调度限制，大镜像（CANN 15-30GB 层）占满内存 |
| v1 | `replicaCount: 1`, `max-parallelism: 4` | 多构建同时跑，但单点 OOM 仍存在 | 多个单阶段构建共享 4 槽位居高不下，64Gi 内存不足时 OOM → 所有进行中构建失败 → 缓存丧失 |
| v2 | `replicaCount: 3`, `max-parallelism: 4` | 当前方案，稳定运行 | 多副本隔离内存空间 + 并行度限制，单副本 OOM 不影响其他副本 |

### 4.2 OOM 触发的恶性循环

```
单个 buildkitd Pod (64Gi 内存)
    │
    ├── CI job A: pip install vllm (torch 编译 ≈ 20GB)
    ├── CI job B: pip install vllm-ascend (numpy+cann ≈ 15GB)
    └── CI job C: apt source + cmake build (≈ 10GB)
           │
    ┌──────┼──────┐
    │  累计 45GB  │
    │  接近 64Gi  │
    └──────┼──────┘
           │
           ▼
    OOM Kill → Pod restart → emptyDir 清空
           │
           ▼
    所有 CI job 失败 → 重试 → 全量重建（无缓存）
```

### 4.3 多副本如何解决问题

```
3 副本 × Pod AntiAffinity（分散到不同物理节点）
         │
    ┌────┼────┬────────────┐
    ▼    ▼    ▼            ▼
   Pod1  Pod2  Pod3
   64Gi  64Gi  64Gi    ← 各自独立内存空间
    │     │     │
    │     │     │
   CI A  CI B  CI C    ← 副本间不共享内存
```

每个副本有独立的内存空间（64Gi）、独立的 `/home/user/.local/share/buildkit` 缓存。无论哪个副本 OOM，只影响该副本上的构建，其他副本不受影响。`podAntiAffinity` 确保副本分散到不同节点，避免单节点内存竞争。

---

## 5. BuildKit 限制与约束

### 5.1 功能限制

| 限制 | 说明 | 影响 |
|------|------|------|
| **不支持 Docker 命令** | Dockerfile 中不能 `RUN docker ...` | 无法嵌套构建、无法启动辅助容器 |
| **不支持 docker-compose** | 无 Docker daemon，不能启动多容器编排 | 集成测试需在 Runner 外完成 |
| **不支持 `--privileged`** | rootless 模式下无特权容器 | 无法调用需要特权的内核功能 |
| **无 docker network/volume** | 不存在 Docker 网络和卷管理 | 构建过程中不能创建/挂载网络卷 |
| **单次构建无内置重试** | `buildctl build` 失败即退出 | 需在 CI 层面加 retry（GitHub Actions `continue-on-error`） |
| **runc 进程隔离** | rootless + `--oci-worker-no-process-sandbox` 跳过 rootlesskit 隔离 | 构建进程以相同 UID 运行，安全性略降 |
| **inline cache 不支持多阶段中间 stage** | `type=inline` 只缓存最终镜像的层 | 多阶段 Dockerfile 的中间 stage 不会缓存（我们的 Dockerfile 都是单阶段，无影响） |
| **镜像仓库仅限 SWR** | Secret 只配置了 SWR 凭证 | 需要推送到 Docker Hub 等其他仓库需额外配置 |

### 5.2 基础设施依赖

| 依赖 | 用途 | 对方案的影响 |
|------|------|-------------|
| `generic-device-plugin` (DaemonSet) | 暴露 `/dev/fuse` 为 K8s 资源 | 必须提前部署，否则 buildkitd Pod 无法调度（`devic.es/fuse: 1` 无法满足） |
| HashiCorp Vault | TLS 证书和 Docker config 注入 | `postStart` hook 失败则 buildkitd 无法启动 TLS 监听 |
| Squid Proxy | 集群外网络出口 | Squid 不可用时，所有外部镜像 pull、apt install、pip install 均失败 |
| nginx-pypi-cache | PyPI / apt / PyTorch / Ascend 缓存代理 | 代理不可用时降级到直连外网（若出口可用） |
| NFS / SFS Turbo | 构建缓存持久化 | rootless user namespace 下 `chown` 失败，不可用 |

### 5.3 性能限制

| 项 | 数据 | 说明 |
|-----|------|------|
| 增量构建耗时 | 2-5 分钟（缓存命中） | 仅构建变更层 |
| 全量构建耗时 | 10-25 分钟（vLLM + CANN） | 取决于网络和 CPU，Squid 代理质量决定 pull 速度 |
| 首层 pull 瓶颈 | base image 15-30GB | 华为 CANN 镜像从 SWR pull，首次无本地缓存时较慢 |
| fuse-overlayfs 开销 | 比内核 overlayfs 慢 15-20% | FUSE 用户态/内核态切换，接受此开销换取 rootless 安全性 |

---

## 6. 适用场景

### 6.1 BuildKit vs Docker 场景对比

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| CI 流水线镜像构建（K8s Runner） | **BuildKit** | 容器内无 Docker daemon；BuildKit 原生支持远程构建 |
| 本地开发调试 | **Docker** | `docker build` 更简单；`docker run -it` 即时验证；`docker-compose` 支持多服务 |
| 多容器集成测试 | **Docker** | 需要 `docker-compose up` 或 `docker network create` |
| 大规模并发 CI 构建 | **BuildKit** | 多副本负载均衡；`max-parallelism` 控制资源 |
| 安全隔离要求高 | **BuildKit rootless** | uid=1000 运行，无需特权容器 |
| Docker-in-Docker (Jenkins) | **Docker sock mount** | 传统 CI 场景，直接挂载 `/var/run/docker.sock` |
| 构建过程需要启动辅助容器 | **Docker** | BuildKit 的 RUN 指令不能 `docker run` |
| GitHub Actions 官方 Runner | **Docker `/setup-buildx-action`** | 官方 runner 有完整的 Docker 环境 |
| GitHub Actions 自托管 K8s Runner | **BuildKit** | 我们的场景，K8s pod 内无 Docker |

### 6.2 何时不适合 BuildKit

1. **Dockerfile 中需要 `RUN docker ...`**：如需要 `docker cp`、`docker run` 启动测试容器
2. **需要 PID/TTY 交互**：BuildKit 不支持 `docker run -it`
3. **需要 docker-compose 编排**：构建 → 启动 → 验证 的流程无法内建
4. **目标仓库未在 Vault 中配置凭证**：当前仅配置了 SWR，推送到其他 registry 需额外配置
5. **构建过程需要特权操作**：如挂载内核模块、操作 `/proc/sys`

### 6.3 当前方案选型理由

```
自托管 ARC Runner (K8s Pod)
    ├── ❌ 无法运行 Docker daemon（需要 privileged + Docker socket）
    ├── ✅ 可以 TCP 连接到 K8s Service (buildkitd-{arch}-service:1234)
    ├── ✅ 构建结果推送到 SWR 镜像仓库
    └── ✅ 通过 Squid + nginx-pypi-cache 走集群内代理访问外部
```

我们选择 BuildKit rootless 的原因是：
1. K8s Pod **无法安全地运行 Docker daemon**（需特权模式）
2. BuildKit rootless 以普通用户运行，符合 K8s 安全最佳实践
3. `buildctl` 是**纯客户端**，只负责发送 Dockerfile 到服务器构建，Runner 自身几乎无负载
4. 多副本可以水平扩展，支撑 8 个 Dockerfile × 2 架构的并行 CI

---

## 7. 版本历史

| 版本 | 日期 | 变更 |
|-----|------|------|
| 2.2 | 2026-07-25 | 新增 BuildKit 限制与约束（§5）、适用场景对比（§6）、并发问题根因分析（§4）；明确 SFS Turbo 与 rootless 不兼容，仅能使用 emptyDir |
| 2.1 | 2026-07-25 | 更新为 inline cache + 双 tag 推送；补充 8 Dockerfile × 2 arch 实际示例；新增 `--find-links` 依赖隔离方案；PVC 当前状态更新为 disabled(emptyDir) |
| 2.0 | 2026-07-22 | DEG 评审初版：设计方案、组件关系、GC 策略、持久化方案 |
| 1.0 | 2026-07-21 | 初始版本 |
