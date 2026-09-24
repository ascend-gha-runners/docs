# 任务失败案例参考

本页收录 runner pod 生命周期中已知的任务失败场景，每个案例附已核实的 GitHub Actions 运行示例，供排障定位参考。

成功运行的 pod 状态流转：**Pending → Running → Succeeded**（终态，pod 随后被移除）

<!-- ERROR_SUMMARY_TABLE_START -->
| 阶段 | 分类 | 错误 |
| :--- | :--- | :--- |
| — | — | [正常流程](#normal-flow) |
| Pending | 镜像 | [镜像名非法](#invalidimagename) |
| Pending | 镜像 | [镜像拉取失败](#errimagepull) |
| Pending | 镜像 | [更换仓库后镜像拉取报 401](#errimagepull-401-unauthorized-after-registry-change) |
| Pending | 镜像 | [镜像未同步到 SWR（not found）](#image-not-synced-to-swr) |
| Pending | 容器创建 | [Secret 配置错误](#createcontainerconfigerror) |
| Pending | 调度 | [调度失败：nodeSelector 不匹配](#failedscheduling-nodeselector) |
| Pending | 调度 | [调度失败：资源超限](#failedscheduling-resource-limit) |
| Pending | 调度 | [调度失败：PVC 不存在](#failedbinding) |
| Pending | 虚拟节点接管 | [Liqo namespace 未接管导致任务卡死](#liqo-offloading-backoff) |
| Running | 容器运行时 | [容器崩溃](#container-crash) |
| Running | 容器运行时 | [内存不足（OOMKilled）](#oomkilled) |
| Running | Workflow | [用户脚本报错](#userscripterror) |
| Running | Workflow | [上传日志 / 产物失败（需加网络白名单）](#upload-artifact-whitelist) |
| Running | 任务卡死 | [任务长时间卡住 / 超时（引擎进程挂起）](#vllm-v1-streaming-hang) |
| Running | 通信 | [HCCL 通信端口被占用](#hccl-port-already-bound) |
| Running | 环境 | [模型缓存缺失 / 不完整](#incomplete-model-snapshot) |
<!-- ERROR_SUMMARY_TABLE_END -->

---

## 正常流程 { #normal-flow }

手动触发正确的 workflow、镜像可拉取时，Pod 状态依次经历 Pending → Running → Succeeded（终态，pod 随后被移除）。

![成功运行：pod 从 Pending 到 Running 再到 Succeeded](assets/error-types/normal-flow.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28346510462)

---

## Pending 阶段（排队）

### 镜像错误

#### 镜像名非法（InvalidImageName） { #invalidimagename }

**现象**：Pod 卡在 **Pending**，K8s reason 为 **`InvalidImageName`**，容器无法创建。

**根因**：workflow 中填写的镜像名格式错误（含非法字符或格式不完整）。

**解决**：[AI] 核对 `container.image` 的镜像名拼写与格式（仓库地址 / 名称 / tag 完整、无非法字符），修正后重新触发 workflow。

![Pod 卡在 Pending，原因 InvalidImageName](assets/error-types/invalid-image-name.png)

> **Ref:**
> [linux-aarch64-test-hook_invalid-image-name · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29319721644)

#### 镜像拉取失败（ErrImagePull） { #errimagepull }

**现象**：Pod 卡在 **Pending**，报 **`ErrImagePull` / `ImagePullBackOff`**，镜像始终拉取不到。

**根因**：镜像不存在、名称或版本写错，或私有镜像缺拉取凭证。

**解决**：[AI] 核对镜像名与 tag 真实存在；若是私有镜像，确认镜像仓库凭证（imagepullsecret）已配置；修正后重新触发。

![Pod 卡在 Pending，报 ErrImagePull / ImagePullBackOff](assets/error-types/err-image-pull.png)

> **Ref:**
> [linux-aarch64-test-hook_err-image-pull · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29319718531)

#### 更换仓库后镜像拉取报 401 { #errimagepull-401-unauthorized-after-registry-change }

**现象**：拉取镜像失败，报 **`401 Unauthorized`**。报错示例（issue #250）：

> `failed to pull and unpack image "swr.<region>.myhuaweicloud.com/<internal-registry>/vllm-ascend:nightly-ci-main-a5": ... failed to authorize: failed to fetch anonymous token: unexpected status: 401 Unauthorized`

**根因**（按 issue #250 定位结论）：业务方把镜像仓库地址从一个 SWR 区域（`swr.<region-a>.myhuaweicloud.com`）改到另一个 SWR 区域（`swr.<region-b>.myhuaweicloud.com`），但 **runner 原本配置的 secret 没有新仓库的拉取权限**，导致 401。

**解决**（按 issue #250 处理过程与建议）：

1. 本次处理：与业务方沟通，**把对应地址的镜像公开**；
2. 长期建议：业务方修改仓库地址前，**先与基础设施方确认对应地址是公开还是私有、当前有没有权限拉取**。

> **Ref:**
> [#250](https://github.com/ascend-gha-runners/docs/issues/250)

#### 镜像未同步到 SWR（not found） { #image-not-synced-to-swr }

**现象**：构建 / 拉取镜像时报 **`failed to resolve source metadata ... not found`**（issue #223）。

> `error: failed to solve: swr.<region>.myhuaweicloud.com/<internal-registry>/vllm-ascend/vllm-ascend:v0.28.0-fd81546-a3: not found`

**根因**（按 issue #223 定位结论）：镜像源变更（如 `quay.io/ascend` → `quay.io/atlas-ci`）后，**SWR 重定向仓库地址未同步更新**，按旧地址拉取时找不到镜像。

**解决**：

1. 对照 sync-tools 的 `image-sync.json` 确认镜像源与 SWR 地址映射；
2. **同步更新 SWR 重定向地址**（如 `.../vllm-ascend` → `.../vllm-ascend-ci`）；
3. 重跑 workflow。

> **Ref:**
> [#223](https://github.com/ascend-gha-runners/docs/issues/223)

### 容器创建错误

#### Secret 配置错误（CreateContainerConfigError） { #createcontainerconfigerror }

**现象**：Pod 卡在 **Pending**，报 **`CreateContainerConfigError`**。

**根因**：workflow 引用了不存在的 Secret。

**解决**：[AI] 核对引用的 Secret 名称拼写，确认该 Secret 已在对应命名空间创建；补建或修正后重新触发。

![Pod 卡在 Pending，报 CreateContainerConfigError（Secret 缺失）](assets/error-types/create-container-config-error.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28346768522)

### 调度错误

#### 调度失败：nodeSelector 不匹配 { #failedscheduling-nodeselector }

**现象**：Pod 卡在 **Pending**，报 **`FailedScheduling`**。

**根因**：没有满足 `nodeSelector` 标签约束的节点。

**解决**：[AI] 检查 `runs-on` / `nodeSelector` 是否有匹配的节点；前往 [Cluster 文档](/docs/Cluster/) 核对标签与机器规格。

![Pod 卡在 Pending，FailedScheduling（nodeSelector 不匹配）](assets/error-types/failed-scheduling-node-selector.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29317874137)

#### 调度失败：资源超限 { #failedscheduling-resource-limit }

**现象**：Pod 卡在 **Pending**，报 **`FailedScheduling`**（422 场景）。

**根因**：申请的 NPU 卡数 / 资源超过该标签节点的上限。

**解决**：[AI] 降低申请的卡数 / 资源，或更换更大规格的标签；前往 [Cluster 文档](/docs/Cluster/) 核对标签与机器规格。

![Pod 卡在 Pending，FailedScheduling（资源超限）](assets/error-types/failed-scheduling-resource.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29317502668)

#### 调度失败：PVC 不存在（FailedBinding） { #failedbinding }

**现象**：Pod 卡在 **Pending**，报 **`FailedBinding`**。

**根因**：workflow 引用的 PVC 不存在。

**解决**：[AI] 核对 PVC 名称、确认 PVC 已在对应命名空间创建；修正后重新触发。

![Pod 卡在 Pending，FailedBinding（PVC 缺失）](assets/error-types/failed-binding-pvc.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29318217127)

### 虚拟节点接管错误

#### Liqo namespace 未接管导致任务卡死（OffloadingBackOff） { #liqo-offloading-backoff }

**现象**：任务长时间 **Waiting**，runner pod 处于 **`OffloadingBackOff`**，无法在目标远端集群（如 gy004）启动；NamespaceOffloading 一直 **`CreationLoopBackOff`**（issue #205）。

**根因**（按 issue #205 定位结论）：远端集群上**预先存在的 namespace 缺少 Liqo 接管标记**，导致 Liqo 拒绝把 pod 反射到该集群（`ReflectionDisabled`），runner 被卡死。

**解决**（按 issue #205 处理过程，**非破坏性**）：

1. 定位任务卡住的集群与 namespace；
2. 给该 namespace 补上与其它集群一致的 Liqo 接管标记：
   - label `liqo.io/remote-cluster-id=cn12-001`
   - annotation `liqo.io/managed-by-namespace-map=<tenant-namespace>/<cluster>`
   - annotation `liqo.io/original-name=<namespace>`
3. 补完即恢复（**不动任何 PVC / SA / namespace 内容**）；
4. 建议把这段标记**固化进部署仓 kustomization**（新增带 label/annotation 的 namespace.yaml 并加入 resources），避免 namespace 被误删 / 漂移再触发。

> **Ref:**
> [#205](https://github.com/ascend-gha-runners/docs/issues/205)

---

## Running 阶段（运行）

### 容器运行时错误

#### 容器崩溃 { #container-crash }

**现象**：**Running** 阶段，容器启动后**立即退出（exit non-zero）**。

**根因**：启动命令错误或依赖（挂载卷 / Secret 等）未就绪。

**解决**：[AI] 核对启动命令与依赖配置，修正后重跑；仍失败带日志登记。

![容器启动后立即以非零码退出](assets/error-types/container-crash-exit.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28562662088)

#### 内存不足（OOMKilled） { #oomkilled }

**现象**：容器被**内核 OOM killer 终止**，状态 **`OOMKilled`**。

**根因**：任务实际内存占用超出申请的 limit。

**解决**：[AI] 在 workflow 中提高内存 limit 后重新触发。

![容器以 OOMKilled 状态终止](assets/error-types/oomkilled.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28570845291)

### Workflow 错误

#### 用户脚本报错（UserScriptError） { #userscripterror }

**现象**：**Running** 阶段，用户脚本 step 以**非零码退出**，K8s pod reason 为 **`Error`**。

**根因**：runner 容器已成功启动、workflow 步骤已执行——失败在脚本逻辑本身。

**解决**：[AI] 属用户脚本问题，按 step 日志定位自行修改，CI 侧不受理。

![用户脚本失败，非零退出码](assets/error-types/user-script-error.png)

> **Ref:**
> [linux-aarch64-test-hook_user-script-error · ascend-gha-runners/add-node-check@3cd45c8](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29319724802)

#### 上传日志 / 产物失败（需加网络白名单） { #upload-artifact-whitelist }

**现象**：上传 artifact / 日志时报 **`Upload progress stalled`**，随后容器 hook 执行失败（`Executing the custom container implementation failed`，exit code 1）（issue #197）。

**根因**（按 issue #197 处理结论）：**上传目标网址未加入网络白名单**，上传被阻断。

**解决**：

1. 确认失败发生在上传 artifact / 日志步骤；
2. 联系基础设施方把上传目标域名**加入网络白名单**（一次性操作，添加后长期有效；多个网址需一并添加）；
3. 重跑 workflow。

> **Ref:**
> [#197](https://github.com/ascend-gha-runners/docs/issues/197)

### 任务卡死 / 超时

#### 任务长时间卡住 / 超时（引擎进程挂起） { #vllm-v1-streaming-hang }

**现象**：任务运行数小时无输出、超时被取消（issue #216：超时 4h5m 后被取消）；pod 显示 **Running** 但日志不再更新。

**根因**（按 issue #216 定位结论）：**vLLM v1 引擎核心进程在流式推理中崩溃 / 死锁**——16 卡 worker 在「投机解码 + DP×TP + 专家并行」推理中挂起，输出队列既无 token 也无收尾，流式客户端永久 `await q.get()`。pod 显示 Running 只是 runner 容器存活，引擎核心已丢失，**属业务代码 / 用例问题**。

**解决**：

1. 查看日志末尾堆栈，若停在 `async_llm.py` 的 `out = q.get_nowait() or await q.get()` 或 `output_processor.py` 的 `raise output`，即可判断为引擎核心挂起（issue #216 结论：之后通过 `await q.get()` 可以快速判断）；
2. 结合启动参数（`--data-parallel-size` / `--tensor-parallel-size`、`--enable-expert-parallel`、`--speculative-config` 等）复现，**属业务代码问题请自行排查**；
3. 无需继续等待可先在 GitHub Actions 页面自行 Cancel，修正后重跑。

> **Ref:**
> [#216](https://github.com/ascend-gha-runners/docs/issues/216)

### 通信错误

#### HCCL 通信端口被占用 { #hccl-port-already-bound }

**现象**：多机任务（如 `DeepSeek-V3_1.yaml` 用例）**Running** 阶段失败，日志报 **`Communication_Error_Bind_IP_Port(EI0019)`**（issue #219）：

> `Cannot bind IF. ip is ***, port is 60000, bind fail. Reason: The IP and port have been bound already.`
> 提示：`maybe the port is occupied by other processes, or there are duplicate startup service processes on the same device`，且 vLLM 实例随之 abort。

**根因**：HCCL 通信端口（如 **60000**）已被其他进程占用，或同一设备上重复启动了服务进程。issue #219 定位为**用户侧用例问题**（业务方用例修改后已无反馈），非 CI 平台问题。

**解决**（按 issue #219 报错中的建议与处理结果）：

1. 检查端口占用情况；
2. 按报错提示，用环境变量 **`HCCL_IF_BASE_PORT`** 调整端口，或用 **`sysctl -w net.ipv4.ip_local_reserved_ports=****-****`** 调整保留端口范围；
3. 检查用例是否在同一设备上**重复启动服务进程**，修正用例后重跑（issue #219 即通过修改业务方用例解决）。

> **Ref:**
> [#219](https://github.com/ascend-gha-runners/docs/issues/219)

### 环境错误

#### 模型缓存缺失 / 不完整 { #incomplete-model-snapshot }

**现象**：**Running** 阶段报模型缓存相关错误，两种形态：

- 缓存**残缺**：`huggingface_hub.errors.IncompleteSnapshotError: The cached snapshot ... is incomplete: N file(s) are missing`（issue #242）；
- 缓存**缺失**：`huggingface_hub.errors.LocalEntryNotFoundError: Cannot find an appropriate cached snapshot folder ... outgoing traffic has been disabled`（issue #220）；或缓存缺 shard（issue #200：`1 valid / 1 missing`）。

**根因**：任务实际调度到的集群上**没有该模型缓存**或**缓存缺文件**，离线模式（`local_files_only=True`）下无法在线补齐。

**解决**（按 issue #242 / #220 / #200 处理过程）：

1. 从报错确认缺失的模型与文件清单（issue #242 给出的排查地址：https://fayespica.github.io/ascend-image-ci/ ）；
2. 确认任务实际调度到的集群上是否有该模型缓存（缺失与残缺都可能，issue #220 确认 gy005 已有对应模型）；
3. 联系基础设施方**补齐 / 重新下载**缺失的模型缓存（issue #242 i2v 已存在、t2v 缺失，重新下载后解决；issue #200 下载缺少的相关模型）；
4. 补齐后重新触发 workflow。

> **Ref:**
> [#242](https://github.com/ascend-gha-runners/docs/issues/242)
> [#220](https://github.com/ascend-gha-runners/docs/issues/220)
> [#200](https://github.com/ascend-gha-runners/docs/issues/200)

---

## 支持

遇到本页未收录的问题，请[发起 discussion](https://github.com/ascend-gha-runners/docs/discussions) 或联系基础设施团队。

---

**Document version:** v2.2
**Last updated:** 2026-09-24
