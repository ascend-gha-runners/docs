# 决策树全量路径表（人工检查用）

> 生成时间：2026-09-28 19:25（由 export_tree_view.py 从 problem-tree.json 自动生成，请勿手改）
> 共 34 条 根→叶子 路径，其中新增 15 条（与 git HEAD 已提交版本对比）
> 步骤列中与上一行相同的留空（等效合并单元格）；— 表示该路径没有这一步
> 已有路径视为已检查过，人工只需复查带 🆕 的新增行（下方清单可勾选）

| 第 1 步 | 第 2 步 | 第 3 步 | 命中案例 | 归属 | 人工复查 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 报错 / Job 失败 | Pending（排队 / 调度） | 镜像拉取失败 | ErrImagePull（镜像拉取失败） | 检查 workflow |  |
|  |  | 镜像名非法 | InvalidImageName（镜像名非法） | 检查 workflow |  |
|  |  | 镜像拉取慢（Initialize containers 卡住） | 镜像拉取慢（Initialize containers 卡住） | 检查 workflow | 🆕 |
|  |  | 容器创建失败（Secret） | CreateContainerConfigError（容器创建失败） | 检查 workflow |  |
|  |  | 容器启动即死（postStart 钩子） | 容器启动即死（postStart 钩子 exit 137） | 基础设施处理 | 🆕 |
|  |  | novolume 模式失败 / 额外耗时 | novolume 模式失败 / 额外耗时 | 基础设施处理 | 🆕 |
|  |  | 调度失败（资源 / 节点） | FailedScheduling（调度失败） | 检查资源申请 |  |
|  |  | 调度到架构不匹配的节点 | 调度到架构不匹配的节点 | 检查 workflow | 🆕 |
|  |  | PVC 不存在 | FailedBinding（PVC 不存在） | 检查 workflow |  |
|  | Running（运行中报错） | 容器退出（崩溃） | Container crash（容器崩溃） | 检查 workflow |  |
|  |  | OOM 内存不足 | OOMKilled（内存不足） | 检查资源申请 |  |
|  |  | /dev/shm 不足 | /dev/shm 不足 | 基础设施处理 | 🆕 |
|  |  | 用户脚本报错 | UserScriptError（用户脚本报错） | 检查 workflow |  |
|  |  | 安装 / 编译阶段 OOM（并行度过高） | 安装 / 编译阶段 OOM（并行度过高） | 检查 workflow | 🆕 |
|  |  | 依赖缓存异常（pypi / rust） | 依赖缓存异常（pypi / rust） | 基础设施处理 | 🆕 |
|  |  | HCCL 通信端口被占用 | HCCL 通信端口被占用 | 检查 workflow |  |
|  |  | 模型缓存缺失 / 不完整 | 模型缓存缺失 / 不完整 | 基础设施处理 |  |
|  |  | 任务长时间卡住 / 超时 | 任务长时间卡住 / 超时（引擎进程挂起） | 检查 workflow |  |
|  |  | 任务耗时异常（模型加载 / checkout） | 任务耗时异常（模型加载 / checkout） | 基础设施处理 | 🆕 |
|  |  | 上传日志 / 产物失败 | 上传日志 / 产物失败（需加网络白名单） | 基础设施处理 |  |
| 一直等待 / 排队 | 可能在等资源（队列满） | — | 等待资源（队列可能已满） | 基础设施处理 |  |
|  | runs-on 标签可能不存在 | — | runs-on 标签可能不存在 | 检查 workflow |  |
|  | Runner 可能未上线 | — | Runner 可能未上线 | 检查 GitHub 配置 |  |
|  | Runner 名额被残留 EphemeralRunner 占用 | — | Runner 名额被残留 EphemeralRunner 占用 | 基础设施处理 | 🆕 |
|  | Runner 版本过旧（GitHub 提升最低版本） | — | Runner 版本过旧（GitHub 提升最低版本） | 基础设施处理 | 🆕 |
|  | 任务卡在虚拟节点（接管异常） | — | 任务卡在虚拟节点（Liqo 接管异常） | 基础设施处理 |  |
| 构建 / 打包失败 | — | — | 构建 / 打包失败 | 检查 workflow |  |
| 集群 / 机器问题 | 弹性节点不缩容 | — | 弹性节点不缩容 | 基础设施处理 |  |
|  | 弹性扩容失败 / 弹性节点不健康 | — | 弹性扩容失败 / 弹性节点不健康 | 基础设施处理 | 🆕 |
|  | 节点 NPU 被外部进程 / 带外容器占用 | — | 节点 NPU 被外部进程 / 带外容器占用 | 基础设施处理 | 🆕 |
|  | 共享盘空间不足 / 锁文件残留 | — | 共享盘空间不足 / 锁文件残留 | 基础设施处理 | 🆕 |
|  | 节点异常（DNS 解析 / 时钟偏移） | — | 节点异常（DNS 解析 / 时钟偏移） | 基础设施处理 | 🆕 |
|  | 节点硬件故障（NPU 挂死 / NotReady） | — | 节点硬件故障（NPU 挂死 / NotReady） | 基础设施处理 | 🆕 |
| 其它 | — | — | 其它问题 | — |  |

## 新增路径复查清单

> 逐条检查路径、案例与归属是否合理；确认后勾选。

- [ ] 报错 / Job 失败 → Pending（排队 / 调度） → 镜像拉取慢（Initialize containers 卡住） → 镜像拉取慢（Initialize containers 卡住）（检查 workflow）
- [ ] 报错 / Job 失败 → Pending（排队 / 调度） → 容器启动即死（postStart 钩子） → 容器启动即死（postStart 钩子 exit 137）（基础设施处理）
- [ ] 报错 / Job 失败 → Pending（排队 / 调度） → novolume 模式失败 / 额外耗时 → novolume 模式失败 / 额外耗时（基础设施处理）
- [ ] 报错 / Job 失败 → Pending（排队 / 调度） → 调度到架构不匹配的节点 → 调度到架构不匹配的节点（检查 workflow）
- [ ] 报错 / Job 失败 → Running（运行中报错） → /dev/shm 不足 → /dev/shm 不足（基础设施处理）
- [ ] 报错 / Job 失败 → Running（运行中报错） → 安装 / 编译阶段 OOM（并行度过高） → 安装 / 编译阶段 OOM（并行度过高）（检查 workflow）
- [ ] 报错 / Job 失败 → Running（运行中报错） → 依赖缓存异常（pypi / rust） → 依赖缓存异常（pypi / rust）（基础设施处理）
- [ ] 报错 / Job 失败 → Running（运行中报错） → 任务耗时异常（模型加载 / checkout） → 任务耗时异常（模型加载 / checkout）（基础设施处理）
- [ ] 一直等待 / 排队 → Runner 名额被残留 EphemeralRunner 占用 → Runner 名额被残留 EphemeralRunner 占用（基础设施处理）
- [ ] 一直等待 / 排队 → Runner 版本过旧（GitHub 提升最低版本） → Runner 版本过旧（GitHub 提升最低版本）（基础设施处理）
- [ ] 集群 / 机器问题 → 弹性扩容失败 / 弹性节点不健康 → 弹性扩容失败 / 弹性节点不健康（基础设施处理）
- [ ] 集群 / 机器问题 → 节点 NPU 被外部进程 / 带外容器占用 → 节点 NPU 被外部进程 / 带外容器占用（基础设施处理）
- [ ] 集群 / 机器问题 → 共享盘空间不足 / 锁文件残留 → 共享盘空间不足 / 锁文件残留（基础设施处理）
- [ ] 集群 / 机器问题 → 节点异常（DNS 解析 / 时钟偏移） → 节点异常（DNS 解析 / 时钟偏移）（基础设施处理）
- [ ] 集群 / 机器问题 → 节点硬件故障（NPU 挂死 / NotReady） → 节点硬件故障（NPU 挂死 / NotReady）（基础设施处理）
