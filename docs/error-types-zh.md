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
| Pending | 镜像 | [镜像拉取慢（Initialize containers 卡住）](#image-pull-slow) |
| Pending | 容器创建 | [Secret 配置错误](#createcontainerconfigerror) |
| Pending | 容器创建 | [容器启动即死（postStart 钩子 exit 137）](#poststart-exit-137) |
| Pending | 容器创建 | [novolume 模式失败 / 额外耗时](#novolume-hook-failures) |
| Pending | 调度 | [调度失败：nodeSelector 不匹配](#failedscheduling-nodeselector) |
| Pending | 调度 | [调度失败：资源超限](#failedscheduling-resource-limit) |
| Pending | 调度 | [调度失败：PVC 不存在](#failedbinding) |
| Pending | 调度 | [调度到架构不匹配的节点](#arch-mismatch) |
| Pending | 虚拟节点接管 | [Liqo namespace 未接管导致任务卡死](#liqo-offloading-backoff) |
| Running | 容器运行时 | [容器崩溃](#container-crash) |
| Running | 容器运行时 | [内存不足（OOMKilled）](#oomkilled) |
| Running | 容器运行时 | [/dev/shm 不足](#dev-shm-oom) |
| Running | Workflow | [用户脚本报错](#userscripterror) |
| Running | Workflow | [上传日志 / 产物失败（需加网络白名单）](#upload-artifact-whitelist) |
| Running | Workflow | [安装 / 编译阶段 OOM（并行度过高）](#compile-oom-threads) |
| Running | Workflow | [依赖缓存异常（pypi / rust）](#dependency-cache-error) |
| Running | Workflow | [任务耗时异常（模型加载 / checkout）](#ci-slow) |
| Running | 任务卡死 | [任务长时间卡住 / 超时（引擎进程挂起）](#vllm-v1-streaming-hang) |
| Running | 通信 | [HCCL 通信端口被占用](#hccl-port-already-bound) |
| Running | 环境 | [模型缓存缺失 / 不完整](#incomplete-model-snapshot) |
| 平台 | 节点资源 | [节点 NPU 被外部进程 / 带外容器占用](#npu-occupied-by-external) |
| 平台 | 存储 | [共享盘空间不足 / 锁文件残留](#shared-storage-lock-and-space) |
| 平台 | 节点异常 | [节点 DNS 解析异常 / 时钟偏移](#node-infra-abnormal) |
| 平台 | 节点异常 | [节点硬件故障（NPU 挂死 / NotReady）](#node-hardware-failure) |
| 平台 | 弹性伸缩 | [弹性扩容失败 / 弹性节点不健康](#elastic-scale-out-failed) |
| 平台 | Runner | [Runner 名额被残留 EphemeralRunner 占用](#ephemeralrunner-stuck) |
| 平台 | Runner | [Runner 版本过旧（GitHub 提升最低版本）](#runner-version-eol) |
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

#### 镜像拉取慢（Initialize containers 长时间卡住） { #image-pull-slow }

**现象**：Pod 停在 **Initialize containers** 阶段很久不前进，镜像在目标架构节点上没有缓存、拉取很慢（issue #271）；有时容器初始化一直卡住（issue #121）。

**根因**：使用了未在 CI 侧缓存的镜像地址（如 `ghcr.io` 直连，见 issue #271 的 `ghcr.io/<vendor>/areal_npu:v1.0.5-a2`），拉取速度慢甚至超时。

**解决**：

1. 改用国内加速镜像源（如 ghcr 南京源 `ghcr.nju.edu.cn/...`）；
2. 若镜像变动不多，可请 CI 侧用 sync-tools 把镜像同步到 SWR 镜像站后改用该镜像；
3. 重跑 workflow。

> **Ref:**
> [#271](https://github.com/ascend-gha-runners/docs/issues/271)
> [#121](https://github.com/ascend-gha-runners/docs/issues/121)

### 容器创建错误

#### Secret 配置错误（CreateContainerConfigError） { #createcontainerconfigerror }

**现象**：Pod 卡在 **Pending**，报 **`CreateContainerConfigError`**。

**根因**：workflow 引用了不存在的 Secret。

**解决**：[AI] 核对引用的 Secret 名称拼写，确认该 Secret 已在对应命名空间创建；补建或修正后重新触发。

![Pod 卡在 Pending，报 CreateContainerConfigError（Secret 缺失）](assets/error-types/create-container-config-error.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28346768522)

#### 容器启动即死：postStart 钩子 exit 137 { #poststart-exit-137 }

**现象**：workflow pod 启动即死，GitHub 侧报 `container "job": Error (exit code 137)`（提示 "Likely OOM" 有误导性）；kubelet 日志报 `Failed to execute PostStartHook: ... failed to drain exec process io in 2s`（issue #257）。

**根因**（按 issue #257 定位结论）：镜像的 `/bin/sh` 指向 **dash**，钩子里 `npu-smi info &> /dev/null` 的 `&>` 是 **bash 语法**；dash 会把它解析为「后台执行」而不是重定向，导致 `npu-smi` 继承了 exec 的 stdout/stderr 管道。containerd 对 exec drain 有 **2s 硬编码超时**，超时即判钩子失败，kubelet 随之连坐 SIGKILL 容器（故 exit 137，并非 OOM）。

**解决**：

1. 把钩子里的 `&> /dev/null` 改成 POSIX 写法 `> /dev/null 2>&1`；
2. 不要在 postStart 里留后台 / 长驻进程（会继承 exec 管道 fd）；
3. 长期把 NPU 就绪等待从 postStart 挪到测试 setup 脚本。

> **Ref:**
> [#257](https://github.com/ascend-gha-runners/docs/issues/257)

#### novolume 模式（runner-container-hooks）失败与额外耗时 { #novolume-hook-failures }

**现象**：novolume 模式下出现多种异常：

- 每个 checkout step 后 copy + hash 校验失败、反复重试（PostCheckout 耗时约 11min，issue #144）；
- `uses:` 本地 / 复合 action 在容器内找不到脚本，报 `can't open file ... No such file or directory`（issue #146）；
- Initialize containers 阶段失败（升级 ARC 0.13.0 + novolume 组合，issue #42 / #44）；
- 每个 step 额外多约 30s（上游 runner-container-hooks#274，issue #66）。

**根因**：上游 runner-container-hooks 的 **novolume 实现缺陷**——Job Pod 卷挂载路径为 `/__w` 而 runner 侧为 `/home/runner/_work`，路径映射不一致；`runScriptStep` 不同步 `_actions/` 目录；`execCpFromPod` 的 tar extract 不清空目标目录，加上 status callback 过早 resolve，导致 hash 校验必然失败。

**解决**：

1. 把 `uses:` 步骤改写为 `run:`（或内联脚本），绕过路径映射解析；
2. 移除多余 setup 步骤，减少 `_temp` 同步量；
3. 升级 ARC / runner-container-hooks 到含修复的版本；
4. 关注上游 runner-container-hooks#337 / #274。

> **Ref:**
> [#42](https://github.com/ascend-gha-runners/docs/issues/42)
> [#44](https://github.com/ascend-gha-runners/docs/issues/44)
> [#66](https://github.com/ascend-gha-runners/docs/issues/66)
> [#144](https://github.com/ascend-gha-runners/docs/issues/144)
> [#146](https://github.com/ascend-gha-runners/docs/issues/146)

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

#### 调度到架构不匹配的节点 { #arch-mismatch }

**现象**：workflow pod 初始化 / 执行失败——lint 任务报 `ModuleNotFoundError: No module named 'rpds.rpds'`（依赖在 aarch64 上不匹配，issue #40 / #46）；或 arm 架构镜像在 amd64 CPU runner 上无法初始化（issue #50）。

**根因**：workflow pod 未限制调度节点，**CPU / lint 任务被调度到 NPU（aarch64）节点**，或容器镜像架构与节点架构不一致。

**解决**：

1. 确认任务实际调度到的节点架构；
2. 为 CPU / lint 任务指定匹配的 **amd64 标签与 nodeSelector**；
3. 使用与节点架构一致的镜像。

> **Ref:**
> [#40](https://github.com/ascend-gha-runners/docs/issues/40)
> [#46](https://github.com/ascend-gha-runners/docs/issues/46)
> [#50](https://github.com/ascend-gha-runners/docs/issues/50)

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

#### /dev/shm 不足 { #dev-shm-oom }

**现象**：多模态用例（如 qwen2.5-VL）在 2 卡等小卡数 runner 上因 **`/dev/shm` 空间不足** 而 OOM，必须换更大规格的机器才能跑过（issue #27）。

**根因**：runner pod 的 `/dev/shm` 默认过小。

**解决**：

1. 平台侧已把 runner 的 `/dev/shm` 调大为 1Gi；
2. 若仍不足，改用 `/dev/shm` 更大的标签；
3. 用例侧降低并发 / 显存占用。

> **Ref:**
> [#27](https://github.com/ascend-gha-runners/docs/issues/27)

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

#### 安装 / 编译阶段 OOM（并行度过高） { #compile-oom-threads }

**现象**：源码编译 / 安装阶段大面积进程被 killed、安装失败（疑似 OOM，issue #112）；更换 runner 标签后卡数被错误解析（如 `a3-800i` 被贪心解析出 `800`，issue #247）。

**根因**：编译脚本按**错误的核心数**推算线程数（实际单卡 CPU 为 23，脚本算出 192，并以 192×2 并发）超出节点可承受；卡数解析正则贪心匹配错误。

**解决**：

1. 在 CI 环境变量**显式指定编译线程数**，不要依赖脚本自动推算；
2. 修正从标签解析卡数的正则（如 `s/.*a3-(800i-)?([0-9]+).*/\2/`）；
3. 按节点实际 CPU 设置并行度。

> **Ref:**
> [#112](https://github.com/ascend-gha-runners/docs/issues/112)
> [#247](https://github.com/ascend-gha-runners/docs/issues/247)

#### 依赖缓存异常（pypi / rust） { #dependency-cache-error }

**现象**：安装依赖报 **`read timeout`**、**`Download failed because not enough bytes were received`**、**`HTTP status server error (503)`**（issue #32 / #98 / #113 / #117）；或依赖下载耗时超过 2h（rust 依赖走官方源，issue #89）。

**根因**：pypi 缓存服务（nginx）上游走华为云——同步不及时 / 被限速时缓存服务自身也拿不到包；未命中缓存时会**外溢到官方源**；keepalive 与 `proxy_read_timeout` 配置不当。rust 等依赖直接走官方源，与国内网络不通。

**解决**：

1. 确认报错来自缓存服务还是已外溢到官方源；
2. 调整缓存服务配置（关闭 keepalive、增大 `proxy_read_timeout`、缩短锁寿命）；
3. 转发镜像站改用 CDN 加速域名；
4. 社区依赖（如 rust）改用国内镜像站。

> **Ref:**
> [#32](https://github.com/ascend-gha-runners/docs/issues/32)
> [#89](https://github.com/ascend-gha-runners/docs/issues/89)
> [#98](https://github.com/ascend-gha-runners/docs/issues/98)
> [#113](https://github.com/ascend-gha-runners/docs/issues/113)
> [#117](https://github.com/ascend-gha-runners/docs/issues/117)

#### 任务耗时异常（模型加载 / checkout） { #ci-slow }

**现象**：模型加载 70G 耗时约 **1100s**（issue #13）；checkout 偶发特别慢（issue #202）。

**根因**：存储带宽不足（issue #13 将模型改放本地存储后达到 1GB/s）；checkout 的网络请求走了模型下载的 IP 被打满（issue #202）。

**解决**：

1. 核对模型加载 / checkout 耗时是否明显异常；
2. 存储侧升级 / 网络侧分流（避免 checkout 与模型下载抢占同一出口）；
3. 属基础设施问题的联系基础设施方。

> **Ref:**
> [#13](https://github.com/ascend-gha-runners/docs/issues/13)
> [#202](https://github.com/ascend-gha-runners/docs/issues/202)

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

## 平台 / 集群错误（集群侧）

### 节点资源被占用

#### 节点 NPU 被外部进程 / 带外容器占用 { #npu-occupied-by-external }

**现象**：runner 调度上后任务在初始化或运行阶段失败——报 **`dcmi model initialized failed, because the device is used. ret is -8020`**（issue #11 / #47）、**`davinci[davinci0] already in use`**（issue #43）；或测试随机 NPU OOM、启动报显存未释放（issue #101 / #225 / #231）。

**根因**：有人在节点上用裸 docker / 本地进程占用 NPU；device-plugin 的分配账本只跟踪 k8s pod，**对带外占用无感知**，仍把该卡分配给 CI 任务。集群混用 default-scheduler 与 volcano 时也会出现「卡已被占用」（issue #43）。

**解决**：

1. pod 内 `npu-smi` 看不到占用进程时，到宿主机（hostPID + `nsenter -t 1 -m`）查 `/dev/davinci*` 的真实持有者；
2. 清理带外容器 / 进程；
3. 规范机器回收流程（确认无容器残留再交回）；
4. 集群统一使用 volcano 调度器；
5. 测试侧 fail-fast：跑用例前查可用 HBM，低于阈值按「环境问题」报错。

> **Ref:**
> [#11](https://github.com/ascend-gha-runners/docs/issues/11)
> [#43](https://github.com/ascend-gha-runners/docs/issues/43)
> [#47](https://github.com/ascend-gha-runners/docs/issues/47)
> [#225](https://github.com/ascend-gha-runners/docs/issues/225)

### 存储错误

#### 共享盘空间不足 / 锁文件残留 { #shared-storage-lock-and-space }

**现象**：报 **`OSError: [Errno 122] Disk quota exceeded`**（issue #191 / #221）、**`failed to create temp dir ... no space left on device`**（issue #252）；或 **`OSError: [Errno 116] Stale file handle`**（issue #72）、多卡任务永久卡在引擎初始化（FileBaton 残留 lock，日志不再更新，issue #187）。

**根因**：共享盘 / 缓存盘配额或空间打满（新集群未预留模型缓存空间；a5 镜像更大，buildkit 保留阈值不足）；共享存储上「文件存在即锁」机制（torch FileBaton、modelscope filelock）在持锁进程被 SIGKILL 后**残留锁文件**，且无超时 / 无 stale 检测。

**解决**：

1. 区分配额（`Errno 122` / EDQUOT）与磁盘满（`Errno 28` / ENOSPC）；
2. 清理缓存 / 扩容共享盘，新集群提前预留模型缓存空间；
3. 调整 buildkit 保留空间阈值并加磁盘告警；
4. 任务卡死时用 py-spy 抓栈确认是否停在 `torch/utils/file_baton.py` 的 `wait()`，删除残留 lock（`find /root/.cache/torch_extensions -name lock -mmin +60 -delete`）；
5. CI 启动步骤加 stale 锁清理；长期把相关 C++ 扩展预编译进镜像。

> **Ref:**
> [#72](https://github.com/ascend-gha-runners/docs/issues/72)
> [#187](https://github.com/ascend-gha-runners/docs/issues/187)
> [#191](https://github.com/ascend-gha-runners/docs/issues/191)
> [#221](https://github.com/ascend-gha-runners/docs/issues/221)
> [#252](https://github.com/ascend-gha-runners/docs/issues/252)

### 节点异常

#### 节点 DNS 解析异常 / 时钟偏移 { #node-infra-abnormal }

**现象**：runner 日志报 **`Could not resolve host: pipelinesghubeus11.actions.githubusercontent.com`**、**`Socket Error: TryAgain`**（issue #48 / #88），任务持续排队无法执行；或安装阶段报 `No module named 'deep_ep'`（torch_npu 下载失败，issue #49）；或 runner 无法注册、arc 向 GitHub 鉴权失败（issue #99）。

**根因**：节点 **DNS 解析插件异常**，runner pod 无法访问 GitHub 中央服务 / 无法下载依赖；或节点**未配置 NTP**，时钟偏移导致鉴权失败。

**解决**：

1. 在 runner pod 内用 `curl -v` / `nslookup` 验证解析，并检查节点时间是否偏移；
2. 确认为节点级故障；
3. 置换该节点；
4. 排查修复 DNS 插件 / 配置 NTP。

> **Ref:**
> [#48](https://github.com/ascend-gha-runners/docs/issues/48)
> [#49](https://github.com/ascend-gha-runners/docs/issues/49)
> [#88](https://github.com/ascend-gha-runners/docs/issues/88)
> [#99](https://github.com/ascend-gha-runners/docs/issues/99)

#### 节点硬件故障（NPU 挂死 / NotReady） { #node-hardware-failure }

**现象**：节点**整机硬挂死**、约 5 分钟后被云平台带外强制复位，Pod 被驱逐、CI 任务失败；`NodeNotReady`；reboot 后 NPU PCIe I/O error 仍存在（issue #152）。

**根因**：Ascend NPU 子系统故障（如 310P 上 ACLGraph capture 加重已在异常态的 NPU 负载，触发整机硬挂死）。

**解决**：

1. 从节点日志确认是否为整机硬挂死 + 带外复位；
2. 该节点需**硬件级 NPU 重置**，reboot 通常无效；
3. 检查同集群同类机型是否同样异常；
4. CI 加前置 NPU 健康检查，异常节点跳过或调度到其他节点重跑；
5. 报华为侧排查固件 / 硬件。

> **Ref:**
> [#152](https://github.com/ascend-gha-runners/docs/issues/152)

### 弹性伸缩

#### 弹性扩容失败 / 弹性节点不健康 { #elastic-scale-out-failed }

**现象**：Pod 长时间 Pending，但 Karpenter 不扩容；NodePool 被置 **`NodeRegistrationHealthy=False`** 后不再重试；或报无库存（issue #226）；runner 模板**写死 `nodeName`** 绕过调度器，节点满时 pod 直接 `phase: Failed`（issue #255）。

**根因**：① Karpenter fork 的 unhealthy 标记无自动恢复；② 单机型 + 单可用区子网无容错；③ 计费 / 账号抖动；④ 部署配置写死 `nodeName`。

**解决**：

1. 清除 NodePool 的 `NodeRegistrationHealthy=False`；
2. 机型列表至少 2 种同级规格，NodeClass 多挂可用区子网；
3. 解除 `nodeName` 硬绑定，改 `nodeSelector: kubernetes.io/arch`；
4. 对 `NodeRegistrationHealthy=False` 及 Pending 超时加告警。

> **Ref:**
> [#226](https://github.com/ascend-gha-runners/docs/issues/226)
> [#255](https://github.com/ascend-gha-runners/docs/issues/255)

### Runner 管理

#### Runner 名额被残留 EphemeralRunner 占用 { #ephemeralrunner-stuck }

**现象**：任务长时间 **`Waiting for a runner to pick up this job`**，runner set 无空闲 slot；`kubectl get ephemeralrunner` 可见 job 已结束的 EphemeralRunner 仍卡在 **`Running`**；带 `TooManyPodFailures` 的失败 ER 不被清理（issue #15 / #39 / #41 / #53 / #54 / #56 / #88）。

**根因**（按 issue #53 定位结论）：ARC 上游 #4148——node drain / pod 终止后 GitHub 侧 runner 已消失，但 K8s 中 EphemeralRunner 卡 `Running`，**占满并发名额**形成调度堵塞；引入 Liqo 虚拟节点后复发更频繁。

**解决**：

1. 查 EphemeralRunner 是否有残留 `Running`，手动删除僵尸 ER 恢复；
2. 升级 ARC 至 **0.13.1** 及以上；
3. 加 EphemeralRunner 超时 12h 告警；
4. 用定时脚本清理未正常退出的 runner。

> **Ref:**
> [#53](https://github.com/ascend-gha-runners/docs/issues/53)
> [#56](https://github.com/ascend-gha-runners/docs/issues/56)

#### Runner 版本过旧（GitHub 提升最低版本） { #runner-version-eol }

**现象**：GitHub 公告提升 self-hosted runner 最低版本后，runner **无法注册 / workflow 不启动**（issue #61 / #116）。

**根因**：GitHub Actions 提升最低 runner 版本（如 2.329.0、2.333.0），平台侧 runner 镜像版本过旧。

**解决**：

1. 跟踪 GitHub changelog 的最低 runner 版本要求；
2. 在 GitHub 更新前替换 / 升级所有 runner 版本；
3. 建立定期升级机制。

> **Ref:**
> [#61](https://github.com/ascend-gha-runners/docs/issues/61)
> [#116](https://github.com/ascend-gha-runners/docs/issues/116)

---

## 支持

遇到本页未收录的问题，请[发起 discussion](https://github.com/ascend-gha-runners/docs/discussions) 或联系基础设施团队。

---

**Document version:** v2.3
**Last updated:** 2026-09-28
