# 软件包缓存使用指导

为了让昇腾 NPU runner 上的 CI 更快、更稳定，我们在集群内为常用包管理器（PyPI、APT、
yum/dnf、rustup）部署了一套缓存代理。命中缓存时，软件包直接从集群内部返回，而不必每次都
从公网下载——这样可以避免网络抖动、上游限流，以及重复下载相同的 wheel 和 `.deb`/`.rpm`
文件。

缓存是**按需开启**的：它不会自动生效。你需要在 workflow 中加入几条配置命令，让
`pip` / `apt` / `dnf` 指向缓存服务。

[已接入仓库](Repo.md)页面会按仓库展示 PyPI 与 APT 缓存当前是否已启用。

## 工作原理

缓存是一个带磁盘存储的 nginx 反向代理，与 runner 部署在同一个 Kubernetes 集群内。它会透明
地代理上游镜像（华为云、官方 PyPI、PyTorch 等），缓存其响应，并在后续请求中直接返回缓存副本。

```
┌───────────────────────────────┐      命中缓存        ┌──────────────────────────┐
│  你的 CI job（runner pod /     │  ──────────────────▶ │  cache-service (nginx)   │
│  container.image）             │                      │  集群内，磁盘缓存        │
│  pip / apt / dnf / rustup      │  ◀──────────────────  │                          │
└───────────────────────────────┘     返回缓存包       └────────────┬─────────────┘
                                                                     │ 未命中
                                                                     ▼
                                                       上游镜像（华为云、pypi.org、
                                                       pytorch.org ...）
```

!!! important
    缓存服务使用的是**集群内部**地址
    （`cache-service.nginx-pypi-cache.svc.cluster.local`）。它只能从**正在运行的 job
    内部**访问，也就是你的 `container.image` 容器内。它无法从你的本地电脑或 GitHub 托管
    runner 访问。下文所有命令都应作为昇腾 NPU runner job 的步骤来执行。

## 准备工作

- 你的仓库已经接入昇腾 NPU runner。如果还没有，请先参考
  [GitHub Actions 接入昇腾算力指导](user-manual-gha-zh.md)。
- 你的 job 在昇腾 runner 上、通过 `container.image` 运行（见文末的 workflow 示例）。

## 服务端点

所有包管理器都访问同一个服务 `cache-service.nginx-pypi-cache.svc.cluster.local`，只是端口
不同：

| 包管理器 | 端口 | 端点 |
| :--- | :---: | :--- |
| pip / PyPI | 80 | `http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple` |
| PyTorch wheel | 80 | `http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/<变体>` |
| APT（Ubuntu / Debian） | 8081 | `cache-service.nginx-pypi-cache.svc.cluster.local:8081` |
| rustup | 8082 | `http://cache-service.nginx-pypi-cache.svc.cluster.local:8082` |
| yum / dnf（openEuler） | 8083 | `http://cache-service.nginx-pypi-cache.svc.cluster.local:8083` |

---

## PyPI（pip）

**你需要做什么**：

在安装任何依赖之前，先让 `pip` 指向缓存：

```bash
pip config set global.index-url http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
pip config set global.trusted-host cache-service.nginx-pypi-cache.svc.cluster.local
```

`trusted-host` 这一行是必需的，因为集群内缓存是通过纯 HTTP 提供的；不加这一行，`pip` 会
拒绝这个“不安全”的 index。

PyPI 缓存以华为云镜像为后端，当镜像尚未同步到刚发布的新包时，会自动回退到官方
`pypi.org` / `files.pythonhosted.org`，所以你无需再额外配置回退源。

!!! tip "使用 uv"
    如果你的项目使用 [uv](https://github.com/astral-sh/uv)，请改用（或同时设置）对应的
    环境变量：

    ```bash
    export UV_INDEX_URL=http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple
    export UV_INSECURE_HOST=cache-service.nginx-pypi-cache.svc.cluster.local
    ```

**怎么验证这步完成**：

- `pip install` 成功，且第二次运行明显更快。
- 响应会带有缓存状态头，你可以直接查看：

  ```bash
  curl -sI http://cache-service.nginx-pypi-cache.svc.cluster.local/pypi/simple/numpy/ \
    | grep -i x-pypi-cache
  # X-Pypi-Cache: HIT   （首次请求为 MISS，之后为 HIT）
  ```

### PyTorch wheel（可选）

如需通过缓存安装 PyTorch 及其配套 wheel，使用 `/whl/<变体>` index（镜像
`download.pytorch.org/whl/<变体>`）：

```bash
pip install torch --index-url http://cache-service.nginx-pypi-cache.svc.cluster.local/whl/cpu
```

把 `cpu` 替换为你需要的变体（如 `cpu`、`cu121`）。缓存会重写 PyTorch index 中的链接，
确保 wheel 下载始终留在集群内部。

---

## APT（Ubuntu / Debian）

**你需要做什么**：

把 APT 源里的上游主机替换为缓存（端口 `8081`），然后照常执行 `apt-get update`。具体改哪个
文件取决于你容器的基础镜像。

=== "Ubuntu 22.04 及更早"

    ```bash
    sed -Ei 's@(ports|archive).ubuntu.com@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list
    apt-get update
    ```

=== "Ubuntu 24.04 及更新（deb822）"

    ```bash
    sed -Ei 's@(ports|archive).ubuntu.com@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list.d/ubuntu.sources
    apt-get update
    ```

=== "Debian 11 及更早"

    ```bash
    sed -Ei 's@deb.debian.org@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list
    apt-get update
    ```

=== "Debian 12 及更新（deb822）"

    ```bash
    sed -Ei 's@deb.debian.org@cache-service.nginx-pypi-cache.svc.cluster.local:8081@g' \
      /etc/apt/sources.list.d/debian.sources
    apt-get update
    ```

!!! note
    较新的 Ubuntu/Debian 镜像采用
    [deb822](https://manpages.debian.org/bookworm/dpkg-dev/deb822.5.en.html) 格式，源
    定义放在 `/etc/apt/sources.list.d/` 下的 `*.sources` 文件里，而不是
    `/etc/apt/sources.list`。如果不确定你的镜像用的是哪种，看哪个文件存在即可。

**怎么验证这步完成**：

- `apt-get update` 和 `apt-get install` 成功，且重复安装更快。
- 缓存返回的响应头中包含 `X-Cache-Status: HIT`。

---

## yum / dnf（openEuler）

**你需要做什么**：

缓存在端口 `8083` 上服务 openEuler 仓库，代理 `repo.huaweicloud.com/openeuler/...`。把每个
`.repo` 文件中的上游主机替换为缓存服务，然后重建元数据缓存：

```bash
sed -Ei \
  -e 's@https?://repo\.openeuler\.org@http://cache-service.nginx-pypi-cache.svc.cluster.local:8083@g' \
  -e 's@https?://mirrors\.openeuler\.org@http://cache-service.nginx-pypi-cache.svc.cluster.local:8083@g' \
  /etc/yum.repos.d/*.repo
dnf clean all && dnf makecache
```

如果你的镜像已经把 `baseurl` 指向华为云，则改写该主机（缓存会去掉它本会重复的 `/openeuler`
前缀）：

```bash
sed -Ei \
  's@https?://repo\.huaweicloud\.com/openeuler@http://cache-service.nginx-pypi-cache.svc.cluster.local:8083@g' \
  /etc/yum.repos.d/*.repo
```

!!! warning "保持 `gpgcheck=1`"
    RPM 签名是端到端校验的，所以通过纯 HTTP 从缓存获取软件包是安全的。**不要**关闭
    `gpgcheck`——关掉它才会真正破坏签名校验。

!!! note "metalink"
    上面的 `sed` 会改写 `metalink=` 行，使其从缓存返回 404（缓存不代理 metalink）。`dnf`
    会自动回退到 `baseurl=`——功能正常，只是多一次往返。若想彻底去掉这一行：

    ```bash
    sed -i '/^metalink=/d' /etc/yum.repos.d/*.repo
    ```

**怎么验证这步完成**：

- 针对改写后的仓库，`dnf makecache` / `dnf install` 成功。
- 缓存返回的响应头中包含 `X-Yum-Cache: HIT`。

---

## rustup（可选）

**你需要做什么**：

如果你的构建通过 `rustup` 安装 Rust 工具链，将其指向端口 `8082` 上的缓存（以华为云 rustup
镜像为后端）：

```bash
export RUSTUP_DIST_SERVER=http://cache-service.nginx-pypi-cache.svc.cluster.local:8082/rustup
export RUSTUP_UPDATE_ROOT=http://cache-service.nginx-pypi-cache.svc.cluster.local:8082/rustup/rustup
```

**怎么验证这步完成**：

- `rustup` / `rustup-init` 下载成功，且工具链压缩包在重复运行时更快返回。
- 缓存返回的响应头中包含 `X-Rustup-Cache: HIT`。

---

## 完整 workflow 示例

一个在昇腾 NPU runner 上运行、并使用 PyPI 与 APT 缓存的完整 GitHub Actions workflow：

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
          # APT（基础镜像为 Ubuntu 22.04；请按你的镜像调整）
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
    把配置缓存的步骤放在**最前面**，先于 `checkout` 和任何 `pip install` /
    `apt-get install`，这样后续每一步都能享受到缓存。

---

## 常见问题

**Q1：我必须使用缓存吗？**

不必。缓存是按需开启的，纯粹是为了提升速度与稳定性。即使不用，你的 job 仍可直接访问公网
镜像正常运行。

**Q2：缓存地址无法解析 / 连接被拒绝。**

- 确认命令是在昇腾 NPU runner 的 job **内部**（`container.image` 容器内）执行的。该服务
  地址是集群内部地址，集群外无法访问。
- 确认包管理器使用了正确的端口（pip 用 80，APT 用 8081，yum/dnf 用 8083，rustup 用
  8082）。

**Q3：缓存里缺少某个包或版本过旧。**

PyPI 缓存在上游镜像尚未同步新发布的包时会自动回退到官方 `pypi.org`，所以这种情况应当很
少见。如果仍遇到过期条目，请[提出 discussion](https://github.com/ascend-gha-runners/docs/discussions)。

**Q4：怎么确认我的仓库被算作“已使用”缓存？**

查看[已接入仓库](Repo.md)页面——它每日进行一次审计，展示每个已接入仓库的 PyPI 与 APT
缓存是否已启用。

---

## 反馈与支持

如果你在配置或使用缓存过程中遇到任何问题，请
[提出 discussion](https://github.com/ascend-gha-runners/docs/discussions)。

提交时，请提供以下信息：

- 项目名称和 Git 仓库地址
- 是哪个包管理器、哪条命令失败
- 错误信息，以及（如有可能）相关的 `X-*-Cache` 响应头
