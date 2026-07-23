# Self-Hosted Runner Actions 兼容性指南

> 适用仓库：[vllm-project/vllm-ascend](https://github.com/vllm-project/vllm-ascend)
> 最后更新：2026-07-20

---

## 结论（TL;DR）

### 可以直接用 ✅

**6 个官方 Action 全部可用** — 无需任何额外配置，把 `runs-on` 改成 self-hosted runner 标签即可：

| Action | 当前使用次数 | 说明 |
|---|---|---|
| `actions/checkout@v7` | 41 | |
| `actions/setup-python@v6` | 3 | |
| `actions/cache@v4` | 替代 `runs-on/cache@v5` | miss/hit + restore/save 均正常 |
| `actions/upload-artifact@v7` | 12 | |
| `actions/download-artifact@v8` | 6 | |
| `actions/github-script@v9` | 5 | |

**3 个第三方 Action 全部可用**：

| Action | 当前使用次数 | 说明 |
|---|---|---|
| `dorny/paths-filter@v4` | 2 | 推荐用于路径变更检测 |
| `tj-actions/changed-files@v47` | 1 | ⚠️ 有供应链安全事件历史，建议替换 |
| `ascend-gha-runners/artifact/upload@v0.3` | 4 | 需 OBS 凭证，无凭证时用标准 upload-artifact 兜底 |

### 需要换方式 ⚠️

**5 个 Docker Action 不可用** — self-hosted runner 没有 Docker daemon，需用 `buildctl` 替代：

| 原 Action | 当前使用次数 | 替代方案 |
|---|---|---|
| `docker/build-push-action@v7` | 3 | `buildctl build`（32核 HK runner 已预配置） |
| `docker/login-action@v4` | 5 | 直接写 Docker config 或 Vault 证书 |
| `docker/setup-buildx-action@v4` | 4 | 远程 buildkitd 已配置，无需 setup |
| `docker/setup-qemu-action@v4` | 1 | 不需要（交叉编译由 buildkitd 处理） |
| `docker/metadata-action@v6` | 2 | ✅ 可以继续用（纯 JS，不需要 Docker） |

### 必须移除 🚫

| Action | 当前使用次数 | 原因 |
|---|---|---|
| `jlumbroso/free-disk-space` | 4 | 会删除宿主机系统包，仅限 GitHub-hosted runner |
| `runs-on/cache@v5` 系列 | 7 | runs-on 服务专用 Action，替换为 `actions/cache@v4` |

### 验证覆盖说明

**已实际验证**（在 self-hosted runner 上跑过）：
- `actions/checkout@v7`、`actions/setup-python@v6`、`actions/cache@v4`、`actions/cache/restore@v4`、`actions/cache/save@v4`、`actions/upload-artifact@v7`、`actions/download-artifact@v8`、`actions/github-script@v9`
- `dorny/paths-filter@v4`、`tj-actions/changed-files@v47`、`ascend-gha-runners/artifact/upload@v0.3`、`peter-evans/create-or-update-comment@v5`
- `docker/metadata-action@v6`、`docker/setup-buildx-action@v4`（验证失败：Docker daemon 不存在）

**未实际验证**（需要 PR/Issue 上下文，`workflow_dispatch` 无法触发）：

| Action | 当前使用次数 | 为什么没验证 |
|---|---|---|
| `peter-evans/slash-command-dispatch@v5` | 1 | 需要 Issue Comment 事件 |
| `actions/stale@v10` | 2 | 需要 Issue/PR 事件 + schedule 触发 |
| `actions/labeler@v6` | 1 | 需要 PR 事件 |
| `github/issue-labeler@v3.4` | 1 | 需要 Issue 事件 |
| `eps1lon/actions-label-merge-conflict@v3` | 1 | 需要 PR 事件 |

> **说明**：以上 5 个 Action 的**核心逻辑不依赖 Docker daemon**，且 GitHub Action 的运行环境（Node.js/Git/网络）在 self-hosted runner 上已验证正常，**推测均可正常使用**。如需确认，可在对应事件触发时观察运行结果。

---

## 一、官方 Actions 使用指南

### 1.1 如何使用

将 workflow 中的 `runs-on` 从 `ubuntu-latest` 改为 self-hosted runner 标签即可，**无需任何额外配置**：

```yaml
# 原来
runs-on: ubuntu-latest

# 改为
runs-on: linux-amd64-cpu-4-hk       # 4 核 HK amd64
runs-on: linux-amd64-cpu-8-hk       # 8 核 HK amd64
runs-on: linux-arm64-cpu-16         # 16 核 guiyang arm64
```

### 1.2 可用 Runner 列表

| Runner 标签 | 架构 | CPU | 内存 | 集群 | 适用场景 |
|---|---|---|---|---|---|
| `linux-amd64-cpu-2-hk` | amd64 | 2 | 8Gi | hk001 | 轻量任务 |
| `linux-amd64-cpu-4-hk` | amd64 | 4 | 8Gi | hk001 | 常规 CI |
| `linux-amd64-cpu-8-hk` | amd64 | 8 | 32Gi | hk001 | 编译任务 |
| `linux-amd64-cpu-16-hk` | amd64 | 16 | 64Gi | hk001 | 大型编译 |
| `linux-amd64-cpu-32-hk` | amd64 | 32 | 128Gi | hk001 | 镜像构建 (buildkitd) |
| `linux-arm64-cpu-8` | arm64 | 8 | 32Gi | gy005 | 常规 CI |
| `linux-arm64-cpu-16` | arm64 | 16 | 64Gi | gy005 | 编译任务 |
| `linux-arm64-cpu-32-hk` | arm64 | 32 | 128Gi | hk001 | 镜像构建 (buildkitd) |

### 1.3 完整示例

```yaml
name: CI on Self-Hosted Runner

on:
  push:
    branches: [main]

defaults:
  run:
    shell: bash -el {0}    # 使用 login shell，确保环境变量加载

permissions:
  contents: read

jobs:
  build:
    runs-on: linux-amd64-cpu-8-hk
    steps:
      - uses: actions/checkout@v7

      - uses: actions/setup-python@v6
        with:
          python-version: '3.12'

      - uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: pip-${{ hashFiles('requirements.txt') }}

      - run: pip install -r requirements.txt

      - uses: actions/upload-artifact@v7
        with:
          name: dist
          path: dist/
```

### 1.4 与 GitHub-hosted 的差异

| 方面 | GitHub-hosted (`ubuntu-latest`) | Self-hosted |
|---|---|---|
| Docker daemon | ✅ 可用 | ❌ 不可用 |
| 每次运行环境 | 全新 VM | 共享 runner pod（ARC 管理） |
| 磁盘空间 | 14GB | 取决于 PVC 大小（64Gi） |
| 缓存 | 仅 GHA cache | GHA cache + 共享 PVC（`/root/.cache`） |
| 网络 | 直连 GitHub | 通过 `gh-proxy.test.osinfra.cn` 代理 |

---

## 二、Docker 构建指南

### 2.1 为什么 Docker Action 不可用

self-hosted runner 运行在 Kubernetes 容器中，**没有 Docker daemon**。所有需要 `/var/run/docker.sock` 的 Docker Action 均无法使用：

```
$ docker buildx create ...
ERROR: failed to connect to docker API at unix:///var/run/docker.sock
dial unix /var/run/docker.sock: connect: no such file or directory
```

> `docker/metadata-action@v6` 是例外 — 它是纯 JS 实现的元数据生成器，不调用 Docker，可以继续使用。

### 2.2 替代方案：buildctl（推荐）

32 核 HK runner 已预配置远程 buildkitd 服务，用 `buildctl` 替代 `docker/build-push-action`：

```yaml
name: Build Docker Image on Self-Hosted

on:
  push:
    branches: [main]

defaults:
  run:
    shell: bash -el {0}

permissions:
  contents: read
  packages: write

jobs:
  build-image:
    runs-on: linux-amd64-cpu-32-hk       # 用 32 核 HK runner
    steps:
      - uses: actions/checkout@v7

      # 1. 生成镜像标签（继续用 docker/metadata-action）✅
      - name: Docker metadata
        id: meta
        uses: docker/metadata-action@v6
        with:
          images: ghcr.io/${{ github.repository_owner }}/my-image
          tags: type=sha

      # 2. 构建并推送（替换 docker/build-push-action）
      - name: Build and push image
        run: |
          IMAGE_TAG=$(echo "${{ steps.meta.outputs.tags }}" | head -1)

          buildctl \
            --addr="$BUILDKITD_ADDR" \
            build \
            --frontend=dockerfile.v0 \
            --local context=. \
            --local dockerfile=. \
            --output "type=image,name=${IMAGE_TAG},push=true" \
            --export-cache "type=registry,ref=${IMAGE_TAG}-cache,mode=max" \
            --import-cache "type=registry,ref=${IMAGE_TAG}-cache"
```

**关键点**：
- `BUILDKITD_ADDR` 环境变量由 32 核 HK runner 的 pod template 自动注入
- Vault 证书（`/home/user/.docker/`）由 pod template 自动注入，`buildctl` 用它做认证
- `--import-cache` / `--export-cache` 提供与 `cache-from: type=gha` 等价的缓存能力
- 多架构构建：切换 `runs-on` 到 `linux-arm64-cpu-32-hk` 即可构建 arm64 镜像

### 2.3 未配置 buildkitd 的 Runner 如何构建

如果需要在非 32 核 runner 上构建镜像，可选择：

| 工具 | 用法 | 适用场景 |
|---|---|---|
| `skopeo` | `skopeo copy docker://A docker://B` | 镜像搬运（不构建） |
| `kaniko` | `/kaniko/executor --destination ...` | 容器内构建，无需 daemon |
| `oras` | `oras push ghcr.io/... my-file` | OCI 制品推送 |

---

## 三、第三方 Actions 使用指南

### 3.1 dorny/paths-filter（路径变更检测）

```yaml
- uses: actions/checkout@v7
  with:
    fetch-depth: 0       # 必须

- uses: dorny/paths-filter@v4
  id: filter
  with:
    filters: |
      source:
        - 'vllm_ascend/**'
        - 'csrc/**'
        - 'setup.py'

- if: steps.filter.outputs.source == 'true'
  run: echo "Source code changed"
```

### 3.2 ascend-gha-runners/artifact/upload

```yaml
# 优先使用 ascend 上传，失败时自动用标准 upload-artifact 兜底
- uses: ascend-gha-runners/artifact/upload@v0.3
  id: ascend-upload
  continue-on-error: true      # 无 OBS 凭证时跳过
  with:
    name: my-artifact
    path: dist/

- if: steps.ascend-upload.outcome != 'success'
  uses: actions/upload-artifact@v7
  with:
    name: my-artifact
    path: dist/
```

### 3.3 peter-evans/create-or-update-comment

```yaml
- uses: peter-evans/create-or-update-comment@v5
  id: comment
  continue-on-error: true     # fork PR 无写权限时优雅降级
  with:
    issue-number: ${{ github.event.pull_request.number }}
    body: |
      ## Build Result
      ✅ Build completed for ${{ github.sha }}
```

> **注意**：当 PR 来自 fork 时，`GITHUB_TOKEN` 对目标仓库无写权限，评论无法发布。这不是 self-hosted runner 的问题，GitHub-hosted runner 上同样存在。只需加 `continue-on-error: true` 即可。

### 3.4 安全提醒

- **替换 `tj-actions/changed-files@v47`** → `dorny/paths-filter@v4`：前者 2025 年 3 月曾有供应链攻击事件
- **移除 `jlumbroso/free-disk-space`**：在 self-hosted runner 上会删除宿主机系统文件，只能用于 GitHub-hosted runner
- **替换 `runs-on/cache@v5`** → `actions/cache@v4`：前者是 runs-on 服务专用 Action，已验证标准 cache 在 self-hosted 上正常工作

---

## 四、并发与性能

### 4.1 并发模型

self-hosted runner 由 ARC (Actions Runner Controller) 在 Kubernetes 上管理：

- **自动扩缩**：ARC 根据任务队列动态创建/销毁 runner pod
- **Matrix 并行**：workflow 的 `strategy.matrix` 自动分发到多个 runner pod
- **资源隔离**：每个 job 运行在独立容器中，互不影响

```yaml
# 多 runner 并行执行
strategy:
  fail-fast: false          # 一个失败不影响其他
  matrix:
    runner:
      - linux-amd64-cpu-8-hk
      - linux-arm64-cpu-16
```

### 4.2 缓存策略

| 缓存类型 | 载体 | 跨 Job | 跨 Run | 跨 Runner |
|---|---|---|---|---|
| `actions/cache@v4` | GitHub 云存储 | ✅ | ✅ | ✅ |
| 共享 PVC (`/root/.cache`) | vllm-project-hk001 | ✅ | ✅ | ✅ |
| pip cache (`~/.cache/pip`) | actions/cache | ✅ | ✅ | ✅ |
| buildkitd 构建缓存 | registry | ✅ | ✅ | ✅ |

**建议**：pip cache 用 `actions/cache@v4`（跨 runner 共享）；编译产物用共享 PVC（免上传下载）。

---

## 五、迁移 Checklist

从 `ubuntu-latest` 迁移到 self-hosted runner 时，逐项检查：

- [ ] `runs-on` 改为合适的 self-hosted runner 标签
- [ ] `actions/cache@v4` 替换 `runs-on/cache@v5`
- [ ] `docker/build-push-action` 替换为 `buildctl build`
- [ ] `docker/login-action` 移除（Vault 证书已处理认证）
- [ ] `docker/setup-buildx-action` / `docker/setup-qemu-action` 移除
- [ ] `jlumbroso/free-disk-space` 移除
- [ ] `tj-actions/changed-files` 替换为 `dorny/paths-filter`
- [ ] `peter-evans/create-or-update-comment` 添加 `continue-on-error: true`
- [ ] `ascend-gha-runners/artifact/upload` 添加标准 upload 兜底
- [ ] `concurrency.group` 按需添加（避免同一 workflow 重复触发）
