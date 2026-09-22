# Job Failure Reference

This page catalogs known job failure scenarios observed across the runner pod lifecycle, with verified GitHub Actions run examples for each case. Use it for troubleshooting or to understand expected behavior.

Expected pod state transitions for a successful run: **Pending → Running → Succeeded** (terminal — pod is then removed)

<!-- ERROR_SUMMARY_TABLE_START -->
| Phase | Category | Error |
| :--- | :--- | :--- |
| — | — | [Normal Flow](#normal-flow) |
| Pending | Image | [InvalidImageName](#invalidimagename) |
| Pending | Image | [ErrImagePull](#errimagepull) |
| Pending | Image | [ErrImagePull: 401 after registry change](#errimagepull-401-unauthorized-after-registry-change) |
| Pending | Container Creation | [CreateContainerConfigError](#createcontainerconfigerror) |
| Pending | Scheduling | [FailedScheduling (nodeSelector)](#failedscheduling-nodeselector) |
| Pending | Scheduling | [FailedScheduling (resource limit)](#failedscheduling-resource-limit) |
| Pending | Scheduling | [FailedBinding](#failedbinding) |
| Running | Container Runtime | [Container crash](#container-crash) |
| Running | Container Runtime | [OOMKilled](#oomkilled) |
| Running | Workflow | [UserScriptError](#userscripterror) |
| Running | Communication | [HCCL Port Already Bound](#hccl-port-already-bound) |
| Running | Environment | [Incomplete Model Snapshot](#incomplete-model-snapshot) |
<!-- ERROR_SUMMARY_TABLE_END -->

---

## Normal Flow

**中文**：正常流程——手动触发正确的 workflow、镜像可拉取，Pod 状态依次经历 Pending → Running → Succeeded（终态，pod 随后被移除）。

Manually trigger the correct workflow with a valid, pullable image. Pod transitions: Pending → Running → Succeeded.

![Successful run showing pod transitions from Pending to Running to Succeeded](assets/error-types/normal-flow.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28346510462)

---

## Pending Phase

### Image Errors

#### InvalidImageName

**中文**：镜像名格式错误。

Invalid image name format.

![Pod stuck in Pending with InvalidImageName reason in GitHub Actions log](assets/error-types/invalid-image-name.png)

> **Ref:**
> [linux-aarch64-test-hook_invalid-image-name · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29319721644)

#### ErrImagePull

**中文**：镜像不存在、名称或版本写错，或私有镜像缺拉取凭证。

Image does not exist.

![Pod stuck in Pending with ErrImagePull and ImagePullBackOff in GitHub Actions log](assets/error-types/err-image-pull.png)

> **Ref:**
> [linux-aarch64-test-hook_err-image-pull · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29319718531)

#### ErrImagePull: 401 Unauthorized After Registry Change

**中文**：更换镜像仓库地址后拉取报 401 Unauthorized——runner 原有 secret 没有新仓库的拉取权限。更换仓库前先与基础设施方确认新仓库是否公开、是否已配置凭证；或将镜像设为公开后重试。

Image pulls fail with `401 Unauthorized` after the registry address was changed (e.g., swr.cn-sourthwest → swr.cn-north-12) — the runner's existing secret has no pull permission for the new registry. Before switching registries, confirm with the infrastructure team whether the new registry is public or credentials exist, or make the image public.

> **Ref:**
> [#250](https://github.com/ascend-gha-runners/docs/issues/250)

### Container Creation Errors

#### CreateContainerConfigError

**中文**：引用了不存在的 Secret。

Referencing a non-existent Secret.

![Pod stuck in Pending with CreateContainerConfigError due to missing Secret](assets/error-types/create-container-config-error.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@22e524c](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28346768522)

### Scheduling Errors

#### FailedScheduling (nodeSelector)

**中文**：nodeSelector 不匹配——没有满足标签约束的节点。

`nodeSelector` mismatch — no node satisfies the label constraints.

![Pod stuck in Pending with FailedScheduling due to nodeSelector mismatch](assets/error-types/failed-scheduling-node-selector.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29317874137)

#### FailedScheduling (resource limit)

**中文**：资源申请超过节点上限（422 场景）。

Resource request exceeds node limit (422 scenario).

![Pod stuck in Pending with FailedScheduling due to resource request exceeding node limit](assets/error-types/failed-scheduling-resource.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29317502668)

#### FailedBinding

**中文**：PVC 不存在。

PVC does not exist.

![Pod stuck in Pending with FailedBinding due to missing PVC](assets/error-types/failed-binding-pvc.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29318217127)

---

## Running Phase

### Container Runtime Errors

#### Container crash

**中文**：容器启动后立即退出（exit non-zero）。

Exit non-zero — container exits immediately after start.

![GitHub Actions log showing container exiting with non-zero exit code immediately after start](assets/error-types/container-crash-exit.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28562662088)

#### OOMKilled

**中文**：内存不足——容器被内核 OOM killer 终止。

Out of memory — container killed by the kernel OOM killer.

![GitHub Actions log showing container terminated with OOMKilled status](assets/error-types/oomkilled.png)

> **Ref:**
> [linux-aarch64-test-hook · ascend-gha-runners/add-node-check@b4b3d9d](https://github.com/ascend-gha-runners/add-node-check/actions/runs/28570845291)

### Workflow Errors

#### UserScriptError

**中文**：用户脚本 step 以非零码退出，K8s pod reason 为 `Error`。与容器崩溃不同：runner 容器已成功启动、workflow 步骤已执行——失败在脚本逻辑本身。

User script step exited with non-zero code. K8s pod reason: `Error`. Unlike container crash, the runner container started successfully and workflow steps executed — the failure is in the script logic itself.

![GitHub Actions log showing user script failure with non-zero exit code](assets/error-types/user-script-error.png)

> **Ref:**
> [linux-aarch64-test-hook_user-script-error · ascend-gha-runners/add-node-check@3cd45c8](https://github.com/ascend-gha-runners/add-node-check/actions/runs/29319724802)

### Communication Errors

#### HCCL Port Already Bound

**中文**：多机任务 Running 阶段报 `Communication_Error_Bind_IP_Port(EI0019)`：IP 与端口（如 60000）已被绑定——端口被其他进程占用，或同一设备上服务进程重复启动。检查端口占用；用环境变量 `HCCL_IF_BASE_PORT` 调整端口，或用 `sysctl -w net.ipv4.ip_local_reserved_ports=****-****` 调整保留端口范围；修正用例后重跑。

Multi-node job fails in Running phase with `Communication_Error_Bind_IP_Port(EI0019): ... The IP address ... and port 60000 have already been bound.` — the port is occupied by another process or the service process was started multiple times on one device. Check port occupancy; adjust via `HCCL_IF_BASE_PORT` or `sysctl -w net.ipv4.ip_local_reserved_ports`; fix the test case and re-run.

> **Ref:**
> [#219](https://github.com/ascend-gha-runners/docs/issues/219)

### Environment Errors

#### Incomplete Model Snapshot

**中文**：Running 阶段报 `IncompleteSnapshotError`：集群侧缓存的模型快照缺文件（`local_files_only=True` 时无法在线补齐）。从报错信息确认缺失的模型与文件清单，联系基础设施方核对 / 补齐对应集群的模型缓存后重新触发。

Running phase fails with `huggingface_hub.errors.IncompleteSnapshotError: The cached snapshot ... is incomplete: N file(s) are missing` (`local_files_only=True`) — the cluster-side model cache is incomplete. Identify the missing model/files from the error message, ask the infrastructure team to verify / complete the model cache on that cluster, then re-trigger the workflow.

> **Ref:**
> [#242](https://github.com/ascend-gha-runners/docs/issues/242)

---

## Support

If you encounter an issue not listed on this page, please [create a discussion](https://github.com/ascend-gha-runners/docs/discussions) or contact the infrastructure team.

---

**Document version:** v2.1
**Last updated:** 2026-09-22
