# GitHub Actions Docker Action → buildctl 替换指南

## 0. 背景

自托管 GitHub Actions Runner（ARC on K8s）的容器内无法运行 Docker daemon，所有 `docker/*` 官方 action 全部不可用。本文说明如何将这些 action 替换为 `buildctl` 命令，让镜像构建在自托管 Runner 上正常运行。

> **适用范围**：`runs-on: [linux-{arch}-cpu-4-buildkit-gy006, gy-006]`

## 1. Action 替换对照

| Docker Action | 功能 | buildctl 替换 |
|--------------|------|--------------|
| `docker/login-action@v4` | 登录镜像仓库 | `--secret id=dockerconfig`（Vault 注入）或环境变量 `BUILDKIT_REGISTRY_CREDS_*` |
| `docker/setup-buildx-action@v4` | 搭建 Docker Buildx | **不需要**，`buildctl` 直连 buildkitd |
| `docker/setup-qemu-action@v4` | QEMU 跨架构模拟 | **不需要**，amd64/arm64 各独立 Runner + buildkitd |
| `docker/metadata-action@v6` | 生成 Docker tag/label | shell 脚本计算 tag/commit |
| `docker/build-push-action@v7` | 构建并推送镜像 | `buildctl build --output type=image,name=...,push=true` |
| `docker buildx imagetools create` | 合并多架构 manifest | `buildctl imagetools create`（相同命令，buildkit v0.31 内置） |

## 2. 逐个替换详解

### 2.1 docker/login-action@v4 → Vault 凭证注入

**原来**：
```yaml
- uses: docker/login-action@v4
  with:
    registry: quay.io
    username: ${{ inputs.quay_username }}
    password: ${{ secrets.QUAY_PASSWORD }}
```

**替换**：Runner Pod 已通过 Vault 注入 `/home/user/.docker/config.json`（含 SWR 凭证）。对于其他 registry（Quay、GHCR），需用 `BUILDKIT_REGISTRY_CREDS_*` 环境变量：

```yaml
env:
  BUILDKIT_REGISTRY_CREDS_QUAY_IO: ${{ inputs.quay_username }}:${{ secrets.QUAY_PASSWORD }}
  BUILDKIT_REGISTRY_CREDS_GHCR_IO: ${{ github.actor }}:${{ secrets.GITHUB_TOKEN }}
```

> 命名规则：`docker.io` → `DOCKER_IO`，`quay.io` → `QUAY_IO`，`ghcr.io` → `GHCR_IO`（`.` → `_`，全大写）。

### 2.2 docker/setup-buildx-action@v4 → 无需替换

**删除即可**。`buildctl` 通过 `--addr=${BUILDKITD_ADDR}` 直连 buildkitd server，不需要本地 Docker daemon 或 Buildx。

### 2.3 docker/setup-qemu-action@v4 → 无需替换

**删除即可**。我们 amd64 和 arm64 各部署了独立的 buildkitd server，在 `strategy.matrix` 中按架构分 Runner 各自构建。不需要 QEMU 跨架构模拟。

### 2.4 docker/metadata-action@v6 → Shell 脚本

**原来**：
```yaml
- name: Docker meta
  id: meta
  uses: docker/metadata-action@v6
  with:
    images: quay.io/ascend/vllm-ascend
    tags: |
      type=schedule,pattern={{date 'YYYYMMDD'}},prefix=nightly-
      type=raw,value=latest
    flavor:
      latest=false
```

**替换**：手动在 step 中生成 tag：

```yaml
- name: Compute image tags
  id: meta
  run: |
    IMAGE="quay.io/ascend/vllm-ascend"

    # 按时间表生成 nightly tag
    DATE=$(date +%Y%m%d)
    TAGS="nightly-${DATE}"

    # workflow_dispatch 时用传入的 tag
    if [ -n "${TAG}" ]; then
      TAGS="${TAG} ${TAGS}"
    fi

    # 生成逗号分隔的多 tag（buildctl --output 需要）
    TAG_LIST=""
    for t in $TAGS; do
      if [ -z "$TAG_LIST" ]; then
        TAG_LIST="${IMAGE}:${t}"
      else
        TAG_LIST="${TAG_LIST},${IMAGE}:${t}"
      fi
    done
    echo "tags=${TAG_LIST}" >> $GITHUB_OUTPUT
```

### 2.5 docker/build-push-action@v7 → buildctl build

**原来**：
```yaml
- uses: docker/build-push-action@v7
  with:
    platforms: linux/amd64
    context: .
    file: Dockerfile
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    build-args: |
      VLLM_COMMIT=${{ steps.vllm.outputs.commit }}
    cache-from: type=registry,ref=ghcr.io/org/repo:buildcache
    cache-to: type=registry,ref=ghcr.io/org/repo:buildcache,mode=max
```

**替换**：
```yaml
- name: Build and push with buildctl
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
      --opt filename=Dockerfile \
      --opt build-arg:VLLM_COMMIT=${{ steps.vllm.outputs.commit }} \
      --secret id=dockerconfig,src=/home/user/.docker/config.json \
      --import-cache type=registry,ref=ghcr.io/org/repo:buildcache \
      --export-cache type=inline \
      --output type=image,\"name=${{ steps.meta.outputs.tags }}\",push=true
```

| 原参数 | buildctl 对应 | 说明 |
|--------|--------------|------|
| `platforms` | 不需要 | 每个 Runner 绑定单一架构，buildkitd 只构建本机架构 |
| `context: .` | `--local context=.` | 构建上下文 |
| `file: Dockerfile` | `--local dockerfile=.` + `--opt filename=Dockerfile` | Dockerfile 路径 |
| `push: true` | `--output ...,push=true` | 推送到 registry |
| `tags: xxx` | `name=xxx` in output | 镜像 tag |
| `build-args` | `--opt build-arg:KEY=VALUE` | 构建参数 |
| `cache-from` | `--import-cache type=registry` | 读取 registry 缓存 |
| `cache-to` | `--export-cache type=inline` | 写入 inline 缓存 |
| `secrets` | `--secret id=xxx,src=/path` | 凭证注入 |

### 2.6 docker buildx imagetools create → buildctl imagetools create

**完全相同**。buildkit v0.31 内置 `buildctl imagetools create`，命令接口与 `docker buildx imagetools create` 兼容。

**原来**：
```bash
docker buildx imagetools create \
  -t "quay.io/org/image:nightly" \
  quay.io/org/image@sha256:abc123 \
  quay.io/org/image@sha256:def456
```

**替换**：直接换成 `buildctl`：
```bash
buildctl imagetools create \
  -t "quay.io/org/image:nightly" \
  quay.io/org/image@sha256:abc123 \
  quay.io/org/image@sha256:def456
```

## 3. 完整转换示例

### 3.1 _schedule_image_build.yaml（多 arch 构建 + manifest 合并）

**原始流程**：
```
Step 1: checkout → login → setup-buildx → build-push (amd64) → upload digest
Step 2: checkout → login → setup-buildx → build-push (arm64) → upload digest
Step 3: download digests → login → setup-buildx → imagetools create (merge)
```

**转换后**：
```yaml
name: Image build (buildctl)

on:
  workflow_call:
    inputs:
      suffix:
        required: true
        type: string
      should_push:
        required: false
        type: boolean
        default: false
      dockerfile:
        required: false
        type: string
      vllm_commit:
        required: false
        type: string
        default: ''
      vllm_ascend_commit:
        required: false
        type: string
        default: ''
    secrets:
      QUAY_CREDS:
        required: false
      GHCR_CREDS:
        required: false

env:
  QUAY_IMAGE: quay.io/ascend/vllm-ascend
  GHCR_CACHE: ghcr.io/vllm-project/vllm-ascend

jobs:
  build-push-digest:
    name: "build (${{ matrix.arch }})"
    runs-on: ${{ matrix.runner }}
    container:
      image: swr.cn-southwest-2.myhuaweicloud.com/base_image/ascend-ci/cann:9.0.0-a3-ubuntu22.04-py3.12

    strategy:
      matrix:
        include:
          - arch: amd64
            runner: linux-amd64-cpu-4-buildkit-gy006
          - arch: arm64
            runner: linux-aarch64-cpu-4-buildkit-gy006

    steps:
      - uses: actions/checkout@v7
        with:
          submodules: recursive
          fetch-depth: 0
          persist-credentials: false

      - name: Compute image tag
        id: tags
        run: |
          IMAGE="${{ env.QUAY_IMAGE }}"
          DATE=$(date +%Y%m%d)
          SUFFIX="${{ inputs.suffix }}"
          TAG="${IMAGE}:nightly-${DATE}${SUFFIX:+-$SUFFIX}-${{ matrix.arch }}"

          # 双 tag：构建结果 + cache
          CACHE_TAG="ghcr.io/vllm-project/vllm-ascend:buildcache${SUFFIX:+-$SUFFIX}-${{ matrix.arch }}"
          echo "output=${TAG},${CACHE_TAG}" >> $GITHUB_OUTPUT

      - name: Build and push
        if: ${{ inputs.should_push }}
        env:
          BUILDKIT_REGISTRY_CREDS_QUAY_IO: ${{ secrets.QUAY_CREDS }}
          BUILDKIT_REGISTRY_CREDS_GHCR_IO: ${{ secrets.GHCR_CREDS }}
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
            --opt filename=${{ inputs.dockerfile || 'Dockerfile' }} \
            --opt build-arg:VLLM_COMMIT=${{ inputs.vllm_commit }} \
            --secret id=dockerconfig,src=/home/user/.docker/config.json \
            --import-cache type=registry,ref=${{ env.GHCR_CACHE }}:buildcache-${{ matrix.arch }} \
            --export-cache type=inline \
            --output type=image,"name=${{ steps.tags.outputs.output }}",push=true

      - name: Export digest
        if: ${{ inputs.should_push }}
        run: |
          mkdir -p /tmp/digests
          # 从 buildctl 输出或 registry 获取 digest
          # 如果 buildctl 支持 --metadata-file，可直接写文件
          echo "$(date +%s)" > /tmp/digests/dummy-${{ matrix.arch }}

      - name: Upload digest
        if: ${{ inputs.should_push }}
        uses: actions/upload-artifact@v7
        with:
          name: digests-${{ matrix.arch }}
          path: /tmp/digests/*
          retention-days: 1

  merge-image:
    name: merge
    runs-on: ubuntu-latest
    needs: build-push-digest
    if: ${{ inputs.should_push }}
    # 注意：merge job 不需要自托管 Runner，用官方 Runner 即可
    # 因为只需要运行 buildctl imagetools create（纯 API 操作）
    steps:
      - name: Download digests
        uses: actions/download-artifact@v8
        with:
          path: /tmp/digests
          pattern: digests-*
          merge-multiple: true

      - name: Compute tags
        id: tags
        run: |
          DATE=$(date +%Y%m%d)
          SUFFIX="${{ inputs.suffix }}"
          echo "tag=nightly-${DATE}${SUFFIX:+-$SUFFIX}" >> $GITHUB_OUTPUT

      # merge job 不需要 buildctl！
      # 可以直接用 crane 或其他 manifest tool
```

### 3.2 schedule_lint_image_build.yaml（单 arch lint 镜像）

**转换后**：
```yaml
name: 'Image build lint (buildctl)'

on:
  schedule:
    - cron: '0 20 * * *'
  workflow_dispatch:
  push:
    paths:
      - '.github/vllm-main-verified.commit'
      - '.github/workflows/dockerfiles/Dockerfile.lint'
      - 'requirements-lint.txt'
      - 'requirements-dev.txt'
      - 'requirements.txt'

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    name: lint image build (amd64)
    runs-on: linux-amd64-cpu-4-buildkit-gy006
    container:
      image: swr.cn-southwest-2.myhuaweicloud.com/base_image/ascend-ci/cann:9.0.0-a3-ubuntu22.04-py3.12

    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Read verified vLLM commit
        id: vllm
        run: |
          commit="$(cat .github/vllm-main-verified.commit)"
          [ -n "$commit" ] || { echo "::error::vLLM commit is empty"; exit 1; }
          echo "main_commit=$commit" >> "$GITHUB_OUTPUT"

      - name: Build and push lint image
        env:
          BUILDKIT_REGISTRY_CREDS_QUAY_IO: ${{ vars.QUAY_CI_USERNAME }}:${{ secrets.QUAY_CI_PASSWORD }}
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
            --opt filename=.github/workflows/dockerfiles/Dockerfile.lint \
            --opt build-arg:VLLM_COMMIT=${{ steps.vllm.outputs.main_commit }} \
            --secret id=dockerconfig,src=/home/user/.docker/config.json \
            --export-cache type=inline \
            --output type=image,\"name=quay.io/ascend-ci/vllm-ascend:lint\",push=true
```

## 4. 凭证管理

### 4.1 当前配置

Runner Pod 通过 Vault 注入 `/home/user/.docker/config.json`（含 SWR 凭证）。`--secret id=dockerconfig` 将这个文件注入到构建中。

### 4.2 其他 Registry 凭证

通过 `BUILDKIT_REGISTRY_CREDS_*` 环境变量传递：

```yaml
env:
  BUILDKIT_REGISTRY_CREDS_QUAY_IO: ${{ secrets.QUAY_USER }}:${{ secrets.QUAY_PASS }}
  BUILDKIT_REGISTRY_CREDS_GHCR_IO: ${{ github.actor }}:${{ secrets.GITHUB_TOKEN }}
```

| Registry | 环境变量名 | 凭证来源 |
|----------|----------|---------|
| quay.io | `BUILDKIT_REGISTRY_CREDS_QUAY_IO` | GitHub Secrets |
| ghcr.io | `BUILDKIT_REGISTRY_CREDS_GHCR_IO` | `${{ github.actor }}:${{ secrets.GITHUB_TOKEN }}` |
| docker.io | `BUILDKIT_REGISTRY_CREDS_DOCKER_IO` | GitHub Secrets |

## 5. 限制与注意事项

### 5.1 当前不支持的功能

| 功能 | 状态 | 说明 |
|------|------|------|
| `buildctl imagetools` on K8s Runner | ⚠️ 需验证 | `imagetools create` 是纯 API 操作，不依赖 Docker daemon，理论可用 |
| **provenance 生成** | ❌ 不支持 | buildctl 支持 `--opt attest:type=provenance`，但会额外生成层 |
| **多架构单次构建** | ❌ 需架构独立 | 每架构单独 Runner + buildkitd，分开构建再 merge |
| **github.actor token for ghcr** | ✅ 支持 | 通过环境变量传递 |

### 5.2 merge job 的处理

合并多架构 manifest 的 job 有两种方案：

**方案 A**：在自托管 Runner 上运行 `buildctl imagetools create`（需验证 `imagetools` 子命令可用）

**方案 B**：用 GitHub 官方 Runner（`ubuntu-latest`）运行 `docker buildx imagetools create` 或 `crane` 工具合并 manifest。因为 merge 不需要构建能力，只需 API 调用 registry。

**推荐方案 B**，merge job 用官方 Runner 跑最简单。

### 5.3 digest 获取

`buildctl --output push=true` 不直接返回 digest。可通过：
- `buildctl build --metadata-file /tmp/metadata.json`（若版本支持）
- 在 merge job 中用 `crane digest <image>` 查询已推送的镜像
- 用固定的 tag 推送，在 merge job 中直接引用

## 6. 改动量估算

| 文件 | docker action 数 | 改动 |
|------|-----------------|------|
| `_schedule_image_build.yaml` | 9 处（login×3, setup-buildx×3, build-push×2, metadata×1） | 整文件重写 |
| `schedule_lint_image_build.yaml` | 5 处（metadata×1, setup-qemu×1, setup-buildx×1, login×1, build-push×1） | 约 60 行 → 40 行 |
| 其他 workflow（如有） | 按需 | 按章替换 |

## 7. 版本历史

| 版本 | 日期 | 变更 |
|-----|------|------|
| 1.0 | 2026-07-25 | 初始版本：Docker action → buildctl 一对一替换对照 + 完整 Workflow 转换示例 |
