# BuildKit 镜像构建用户手册

> 适用场景：在 self-hosted K8s Runner 上用 `docker/build-push-action@v7` 构建镜像。
> 底层服务由 infra 团队维护，用户只需关注 Dockerfile 和 Workflow。

## 1. 快速开始

Workflow 跟 GitHub 官方 Runner 上写的一模一样，只需指定 `runs-on` 为 buildkit runner：

```yaml
name: Build Image
on: push

jobs:
  build:
    strategy:
      matrix:
        arch: [amd64, arm64]
    runs-on: ${{ matrix.arch == 'amd64' && 'linux-amd64-cpu-4-buildkit-gy006' || 'linux-aarch64-cpu-4-buildkit-gy006' }}
    name: build (${{ matrix.arch }})
    container:
      image: <你的基础镜像>

    steps:
      - uses: actions/checkout@v7

      - uses: docker/build-push-action@v7
        with:
          context: .
          file: Dockerfile
          push: true
          tags: |
            quay.io/myorg/myimage:${{ matrix.arch }}-${{ github.sha }}
          build-args: |
            VERSION=1.0
          cache-from: type=registry,ref=quay.io/myorg/myimage:cache-${{ matrix.arch }}
          cache-to: type=inline
          provenance: false
```

**和官方 Runner 的区别只有 `runs-on`。**

## 2. Dockerfile 编写规范

### 2.1 单阶段 vs 多阶段

当前所有 Dockerfile 为**单阶段**构建，搭配 `cache-to: type=inline` 使用。

如果未来需要多阶段构建，将 `cache-to` 改为 `type=registry,mode=min` 即可，中间 stage 缓存由 registry 存储。

```dockerfile
FROM swr.cn-xxx.myhuaweicloud.com/your-base-image:tag

# ARG 默认值用公开地址 → 本地 `docker build .` 直接可用
# CI 通过 workflow 的 build-args 覆盖为集群内部地址（更快更稳定）
ARG APTMIRROR
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cpu
ARG ASCEND_INDEX_URL=https://mirrors.huaweicloud.com/ascend/repos/pypi

# 1. 系统依赖
RUN apt-get install -y gcc cmake

# 2. Python 依赖
RUN pip config set global.index-url ${PIP_INDEX_URL}
RUN pip install torch numpy

# 3. 克隆代码
RUN git clone https://github.com/org/repo.git /workspace/repo

# 4. 安装项目（--find-links 避免依赖污染）
RUN pip install -e /workspace/repo --find-links ${PYTORCH_INDEX_URL}/torch/
```

### 2.2 依赖索引选择

| 依赖 | 推荐索引 | 说明 |
|------|---------|------|
| 普通 Python 包 | `${PIP_INDEX_URL}`（默认 PyPI 代理） | 常规 pip 包 |
| `mooncake-transfer-engine-npu` | `${MOONCAKE_INDEX_URL}`（默认 ali 云镜像） | Mooncake 专用包 |
| `torch==2.x+cpu` | `${PYTORCH_INDEX_URL}/torch/`（`--find-links`） | CPU 版本 torch |
| `triton-ascend` | `${ASCEND_INDEX_URL}`（`--extra-index-url`） | Ascend 专用包 |
| apt 源 | `${APTMIRROR}` | 系统包 |

### 2.3 关键注意事项

1. **不要用 `--extra-index-url` 拉 torch CPU wheel**  
   会引入 PyTorch CDN 的 jinja2/numpy 等包，hash 与 PyPI 不同 → 构建失败。改用 `--find-links`。

2. **`triton-ascend==3.2.1` 只存在于 Ascend 仓库**  
   PyPI 上只有 3.2.0，必须用 `${ASCEND_INDEX_URL}`。

3. **单阶段 → inline，多阶段 → mode=min**  
   当前仓库为单阶段构建，`cache-to: type=inline` 最优。  
   如果切换为多阶段构建，改用 `cache-to: type=registry,mode=min`。

4. **Dockerfile 默认地址公开，CI 自动覆盖为集群内部**

   ARG 默认值使用公开镜像源，保证本地 `docker build .` 可以直接运行。
   Workflow 在 `build-args` 中覆盖为集群内部代理，CI 时自动加速：

   ```yaml
   - uses: docker/build-push-action@v7
     with:
       build-args: |
         PIP_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
         PIP_TRUSTED_HOST=cache-service.nginx-pypi-cache.svc.cluster.local
         PYTORCH_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/cpu
         ASCEND_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/ascend/repos/pypi
         MOONCAKE_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
         GIT_PROXY=https://gh-proxy.test.osinfra.cn/
   ```

5. **Git clone 走代理** — CI 时 buildkitd server 无法直接访问 GitHub。

   Dockerfile 中添加：
   ```dockerfile
   ARG GIT_PROXY=""
   RUN if [ -n "$GIT_PROXY" ]; then \
         git config --global url."${GIT_PROXY}https://github.com/".insteadOf https://github.com/; \
       fi && \
       git clone --depth 1 -b $VLLM_TAG $VLLM_REPO /vllm-workspace/vllm
   ```
   本地 `docker build .` → `GIT_PROXY=""` 跳过 → 直连 GitHub ✅  
   CI → workflow 注入 `GIT_PROXY=https://gh-proxy.test.osinfra.cn/` ✅

## 3. Workflow 编写规范

### 3.1 完整模板（单架构）

```yaml
name: Build
on: push

jobs:
  build:
    runs-on: linux-amd64-cpu-4-buildkit-gy006   # ← 唯一需要改的
    container:
      image: <你的基础镜像>

    steps:
      - uses: actions/checkout@v7

      - uses: docker/build-push-action@v7
        with:
          context: .
          file: Dockerfile
          push: true
          tags: quay.io/org/image:latest
          build-args: |
            APTMIRROR=http://cache-service.nginx-pypi-cache.svc.cluster.local:8081
            PIP_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
            PIP_TRUSTED_HOST=cache-service.nginx-pypi-cache.svc.cluster.local
            PYTORCH_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/cpu
            ASCEND_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/ascend/repos/pypi
            MOONCAKE_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
            GIT_PROXY=https://gh-proxy.test.osinfra.cn/
          cache-from: type=registry,ref=quay.io/org/image:cache
          cache-to: type=inline
          provenance: false
```

### 3.2 多架构构建（matrix + merge）

```yaml
jobs:
  build:
    strategy:
      matrix:
        include:
          - arch: amd64
            runner: linux-amd64-cpu-4-buildkit-gy006
          - arch: arm64
            runner: linux-aarch64-cpu-4-buildkit-gy006
    runs-on: ${{ matrix.runner }}
    container:
      image: <你的基础镜像>

    steps:
      - uses: actions/checkout@v7

      - uses: docker/build-push-action@v7
        with:
          push: true
          tags: quay.io/org/image:${{ matrix.arch }}-${{ github.sha }}
          cache-from: type=registry,ref=quay.io/org/image:cache-${{ matrix.arch }}
          cache-to: type=inline
          provenance: false

  merge:
    needs: build
    runs-on: ubuntu-latest        # ← merge 用官方 Runner，不需要 buildkit
    steps:
      - name: Merge manifests
        run: |
          docker buildx imagetools create \
            -t quay.io/org/image:latest \
            quay.io/org/image:amd64-${GITHUB_SHA} \
            quay.io/org/image:arm64-${GITHUB_SHA}
```

### 3.3 参数说明

| 参数 | 值 | 说明 |
|------|-----|------|
| `runs-on` | `linux-{arch}-cpu-4-buildkit-gy006` | 必须用 buildkit runner |
| `push` | `true` | 推送到镜像仓库 |
| `cache-from` | `type=registry,ref=...` | 从 registry 读取缓存 |
| `cache-to` | `type=inline` | 缓存嵌入镜像（不需要单独推送） |
| `provenance` | `false` | 固定 false，避免额外层 |

## 4. 多项目接入

### 4.1 新项目接入步骤

1. **确认 runner 存在**：向 infra 团队确认目标集群已有 buildkit runner
2. **编写 Dockerfile**：参照 §2 规范
3. **编写 Workflow**：参照 §3 模板，改 `runs-on` 为正确的 runner 名称
4. **创建 PR**：正常提交即可，CI 自动使用 buildkitd 构建

### 4.2 Runner 命名规范

```
linux-{arch}-cpu-{cores}-buildkit-{cluster}
```

示例：
| Runner | 架构 | 集群 |
|--------|------|------|
| `linux-amd64-cpu-4-buildkit-gy006` | x86_64 | 贵阳 006 |
| `linux-aarch64-cpu-4-buildkit-gy006` | ARM64 | 贵阳 006 |

### 4.3 可用 Runner 查询

在仓库 Settings → Actions → Runners 页面查看已注册的 self-hosted runners。

## 5. 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| `docker: unknown command: docker buildx` | Runner 初始化未完成 | 重试 CI |
| `Cannot connect to docker daemon` | Builder 未配置 | 检查 runner 标签是否正确 |
| `hash mismatch for jinja2` | 错误使用了 `--extra-index-url` | 改用 `--find-links ${PYTORCH_INDEX_URL}` |
| 构建速度慢 | 首次全量构建无缓存 | 后续增量构建 2-5 分钟 |
| 镜像导出慢（占 2/5 总时间） | CANN 基础镜像 15-30GB，经 Squid 代理推送 | 属于正常现象；取消 `buildkit-cache` tag 可减少一次推送 |

## 6. 参考

- [PR #278](https://github.com/nv-action/vllm-benchmarks/pull/278) — group3: Dockerfile.a5 + Dockerfile.a5.openEuler
- [PR #279](https://github.com/nv-action/vllm-benchmarks/pull/279) — group1: Dockerfile + Dockerfile.310p + Dockerfile.310p.openEuler
- [PR #280](https://github.com/nv-action/vllm-benchmarks/pull/280) — group2: Dockerfile.a3 + Dockerfile.a3.openEuler + Dockerfile.openEuler
