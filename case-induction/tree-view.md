# 决策树全量路径表（人工检查用）

> 生成时间：2026-09-22 19:41（由 export_tree_view.py 从 problem-tree.json 自动生成，请勿手改）
> 共 16 条 根→叶子 路径，其中新增 3 条（与 git HEAD 已提交版本对比）
> 步骤列中与上一行相同的留空（等效合并单元格）；— 表示该路径没有这一步
> 已有路径视为已检查过，人工只需复查带 🆕 的新增行（下方清单可勾选）

| 第 1 步 | 第 2 步 | 第 3 步 | 命中案例 | 归属 | 人工复查 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 报错 / Job 失败 | Pending（排队 / 调度） | 镜像拉取失败 | ErrImagePull（镜像拉取失败） | 检查 workflow |  |
|  |  | 镜像名非法 | InvalidImageName（镜像名非法） | 检查 workflow |  |
|  |  | 容器创建失败（Secret） | CreateContainerConfigError（容器创建失败） | 检查 workflow |  |
|  |  | 调度失败（资源 / 节点） | FailedScheduling（调度失败） | 检查资源申请 |  |
|  |  | PVC 不存在 | FailedBinding（PVC 不存在） | 检查 workflow |  |
|  | Running（运行中报错） | 容器退出（崩溃） | Container crash（容器崩溃） | 检查 workflow |  |
|  |  | OOM 内存不足 | OOMKilled（内存不足） | 检查资源申请 |  |
|  |  | 用户脚本报错 | UserScriptError（用户脚本报错） | 检查 workflow |  |
|  |  | HCCL 通信端口被占用 | HCCL 通信端口被占用 | 检查 workflow | 🆕 |
|  |  | 模型缓存不完整 | 模型缓存不完整 | 基础设施处理 | 🆕 |
| 一直等待 / 排队 | 可能在等资源（队列满） | — | 等待资源（队列可能已满） | 基础设施处理 |  |
|  | runs-on 标签可能不存在 | — | runs-on 标签可能不存在 | 检查 workflow |  |
|  | Runner 可能未上线 | — | Runner 可能未上线 | 检查 GitHub 配置 |  |
| 构建 / 打包失败 | — | — | 构建 / 打包失败 | 检查 workflow |  |
| 集群 / 基础设施问题 | 弹性节点不缩容 | — | 弹性节点不缩容 | 基础设施处理 | 🆕 |
| 其它 | — | — | 其它问题 | — |  |

## 新增路径复查清单

> 逐条检查路径、案例与归属是否合理；确认后勾选。

- [ ] 报错 / Job 失败 → Running（运行中报错） → HCCL 通信端口被占用 → HCCL 通信端口被占用（检查 workflow）
- [ ] 报错 / Job 失败 → Running（运行中报错） → 模型缓存不完整 → 模型缓存不完整（基础设施处理）
- [ ] 集群 / 基础设施问题 → 弹性节点不缩容 → 弹性节点不缩容（基础设施处理）
