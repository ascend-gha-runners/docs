# CI 缓存审计策略

本文档说明 [check-cache-audit.yml](https://github.com/ascend-gha-runners/docs/blob/main/.github/workflows/check-cache-audit.yml)
每日审计的检测策略：每个缓存维度**查什么、去哪里查、如何判定**，以及已知局限。
判定逻辑的实现见 `scripts/ci-audit/check_cache_from_logs.sh`（v5）。

## 审计要回答的问题

对每个接入 NPU runner 的仓库，回答：**它的 CI 是否实际受益于集群提供的各类缓存**，
从而知道哪些仓库需要接入/修复缓存配置，以及各缓存基础设施的真实利用率。

标记图例：

| 标记 | 含义 |
| :---: | :--- |
| ✅ | confirmed in use（已确认在用） |
| ❌ | confirmed NOT in use（已确认未用） |
| - | unknown（无法判定） |

## 核心原则：两类缓存，两套检测路径

集群缓存按「配置方在哪一侧」分为两类，这决定了可靠的检测数据源：

### A 类：项目自配型

缓存是否生效取决于**项目仓库自己的配置**，项目 workflow 和 job 日志里都有可见痕迹。

| 维度 | 项目侧配置形态 | 日志侧可见痕迹 |
| :--- | :--- | :--- |
| PyPI | `pip config` / `PIP_INDEX_URL` / `UV_INDEX_URL` 指向 nginx-pypi-cache | `Looking in indexes: http://cache-service.nginx-pypi-cache...` |
| APT | `sources.list` / `Acquire::http` 指向 apt 缓存端口 | `Get:/Hit:` 行出现缓存主机 |
| CCache | 安装并启用 ccache | `cache hit/miss` 统计、`CC=ccache` 等 |
| uv | 使用 uv 命令 | `uv pip/sync` 输出 |
| runs-on/cache | workflow 中引用 `runs-on/cache@v5` | `Cache restored/saved from key` |

**检测路径：扫 job 日志为主**（日志能证明"实际用了"而非"配置了"），workflow 静态扫描仅作 runs-on 的补充。
反面证据（如 `Looking in indexes: https://pypi.org/simple`）用于判 ❌。

### B 类：基建注入型

缓存由 **ascend-ci-deployment 仓库的 runner pod template 注入**，对项目仓库完全透明——
项目 workflow 里不存在任何相关配置，job 日志里也几乎没有直接痕迹。
**扫项目仓库来判定 B 类必然得到错误结论**（这正是 v4 的 bug，见下文）。

| 维度 | 注入方式（部署仓库侧） | 接线位置 |
| :--- | :--- | :--- |
| BuildKit | postStart 执行 `buildkit-acquire`（向 dispatcher 租约独占 worker）+ `docker buildx create --name buildkitd --driver remote --use`；共享 buildkitd 的 PVC 层缓存由服务端 GC 自动管理 | `projects/{org}/{repo}/config*/\*configmap\*.yaml` |
| Squid | runner/job pod env 注入 `HTTP_PROXY=http://squid-cache.squid.svc.cluster.local:3128`（含 NO_PROXY 与 CA bundle） | pod template configmap + 各 scale set `values.yaml` |
| git-cdn | postStart `git config --system url."http://git-cdn-service.git-cdn...".insteadOf https://github.com/` 透明改写 | pod template configmap |

**检测路径：部署仓库接线状态为权威判定 + job 日志运行时证据为补充**：

1. **部署侧（权威，0 API 调用）**：workflow 先浅克隆
   `opensourceways/ascend-ci-deployment`，脚本按 `githubConfigUrl`（values.yaml，
   目录名可能是旧 org 名，如 `volcengine/verl` → `verl-project/verl`）定位项目根目录，
   在其中 grep 接线特征：
   - BuildKit：`buildkit-acquire|docker buildx create|BUILDKITD_ADDR`
   - Squid：`squid-cache.squid.svc.cluster.local|squid-ca-cert`
   - git-cdn：`git-cdn-service`
2. **日志侧（运行时补充）**：见下表。注意 B 类的日志证据天然稀疏，找不到不代表没用。

### B 类各维度的日志证据

| 维度 | 正面证据（→✅） | 反面证据（→❌） |
| :--- | :--- | :--- |
| BuildKit | `#0 building with "buildkitd" instance using remote driver`（**实锤**：builder 名固定为 buildkitd、remote driver，可与本地 dind 区分）；`#5 CACHED` / `=> CACHED`（缓存命中，两种 progress 格式）；`importing/exporting cache`；`#N [internal] load ...`（buildkit 进度格式，弱证据） | `Step N/M :`（legacy builder）；`Cannot connect to the Docker daemon` / `docker: command not found`（未接线 runner 上构建无法发生） |
| Squid | runner 打印的 `Runner is running behind proxy server 'http://squid-cache.squid.svc...'` | —（代理透明，日志无反面证据可言） |
| git-cdn | git 报错/verbose 输出中露出 `git-cdn-service.git-cdn...` 真实 URL | —（url 改写透明） |

### 判定优先级（B 类）

```
日志运行时正面证据 ✅ > 部署侧已接线 ✅ > 日志反面证据 ❌ > 部署侧未接线 ❌ > 未在部署仓库找到该项目 -
```

- 部署侧"已接线"即判 ✅：接线后任何 `docker build`/`docker buildx build`/HTTP 请求/git clone
  都会自动走共享缓存，不需要项目做任何事；
- 部署侧"未接线"判 ❌：该项目的 runner 不会路由到对应缓存（无论项目是否想用）；
- 部署仓库中找不到该项目（如尚未部署、或经 Fork 同步的镜像仓库）判 `-`。

## v4 → v5 修复的三个 bug（含真实案例）

2026-11-23 的审计 run 数据验证了 v4 的三个系统性错误：

1. **BuildKit 静态扫描找错了对象**：v4 在**项目** workflow 里找
   `cache-from|cache-to|--import-cache|--export-cache|buildcache`。共享 buildkitd
   架构下项目**不需要**这些 flag（缓存服务端自动生效），这组 pattern 检测的是
   "项目往 registry 导出缓存"——另一个概念。
   - 假阳性：`sgl-project/sglang`、`verl-project/verl` 的 workflow 含 registry cache
     配置（其构建 job 实际跑在 GitHub 托管 runner 上）→ 被误标 ✅；
   - 假阴性：最大用户 `vllm-ascend`（裸 `docker buildx build`）无任何匹配 → `-`。
2. **BuildKit 反面证据整个反转**：日志出现 `buildkitd`（builder 名、endpoint、
   `docker buildx ls` 输出）恰是"接着我们的远程 buildkitd"的直接证据，v4 却判
   ❌"用buildkit但无缓存指令"。真实案例：`Ascend/cann-container-image`（已接线，
   日志里有 `#10 [cann-installer 2/7] RUN ...` 构建输出）被误标 ❌。
3. **Squid 日志 pattern 假阳性**：匹配裸 `:3128`/`HTTP_PROXY`，把项目自配代理
   当成我们的缓存。真实案例：`verl-project/uni-agent` 的
   `HTTP_PROXY: "http://100.68.174.87:3128"`（项目自己的代理）被误标 ✅。
   v5 只匹配 `squid-cache.squid.svc.cluster.local`。

另注：v4 的 `=> CACHED|CACHED \[` 只覆盖 TTY/auto progress 格式；GHA 里 stdout
是管道，buildx 走 plain progress，命中行是 `#5 CACHED`——v4 漏掉了绝大多数真实
缓存命中。v5 两种格式都覆盖。

## 新增 git-cdn 列

B 类第三个维度 git-cdn 此前没有列。v5 起表格为 8 列（PyPI / APT / CCache / uv /
BuildKit / Squid / git-cdn / runs-on），`update_repo_md.py` 会把 7 列旧表自动迁移
（在 Squid 后插入 git-cdn 列，旧值保留）。

## 已知局限

- **首建无命中**：冷缓存上的第一次构建没有 `CACHED` 行（缓存只写不读）。
  因此日志证据把"buildkit 进度格式"也算正面证据（只要部署侧接线，就是我们的缓存）。
- **日志不可用**：日志过期/下载失败时，B 类维度靠部署侧接线兜底（这正是权威判定的
  价值——vllm-ascend 长期"log download failed"，v4 只能给 `-`，v5 给出确定结论）；
  A 类维度则只能保留旧值（见下）。
- **旧值保持规则**：`update_repo_md.py` 在新结果为 `-` 时保留 Repo.md 旧值。这是
  刻意的（避免一次扫不到就清空），但也意味着历史假阳性会一直留到被新证据推翻——
  B 类维度的部署侧判定恰好提供这种确定性推翻。
- **部署克隆时效**：部署仓库浅克隆是审计时刻的 HEAD；接线变更后最长延迟一个
  审计周期（每日 10:24 CST）。
- **progress 格式的歧义**：`#N [x/y]` 进度格式无法区分我们的远程 buildkitd 与
  本地 dind（`building with "buildkitd" ... remote driver` 才能区分）；仅当部署侧
  同时显示未接线时才作为可疑信号记入证据。

## 实现索引

| 文件 | 职责 |
| :--- | :--- |
| `.github/workflows/check-cache-audit.yml` | 每日调度；克隆部署仓库；调审计脚本；回写 Repo.md |
| `scripts/ci-audit/check_cache_from_logs.sh` | 主体：Phase 1 收集 NPU job 候选，Phase 2 聚合日志证据，部署侧接线判定（`scan_deployment_wiring`） |
| `scripts/ci-audit/update_repo_md.py` | 把审计结果合并进 Repo.md 表格（8 维 + 旧表迁移） |
| `scripts/ci-audit/discover_new_repos.py` | 从部署仓库 projects/ 发现新接入仓库 |
| `scripts/ci-audit/repos.txt` | 仓库清单 + 各维度默认值（8 列） |
