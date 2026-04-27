# Buildkite CI 流水线对接文档

## 一、整体架构概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Buildkite 调度层                                │
│                         (pipeline.yml 定义任务流程)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Buildkite Agent Stack K8s                             │
│            (在 Kubernetes 集群中运行的 buildkite-agent)                     │
│                    queue: ascend-a3 / ascend-a2b3                          │
└─────────────────────────────────────────────────────────────────────────────┘
                    │                                           │
                    ▼                                           ▼
        ┌───────────────────────┐               ┌───────────────────────┐
        │    CN12-001 集群       │               │     HK-001 集群       │
        │   (Ascend 910A3)      │               │   (Ascend 910A2B3)    │
        │                       │               │                       │
        │ - Namespace: vllm-project      │     │ - Namespace: vllm-project │
        │ - PVC: 1200Gi (SFS Turbo)      │     │ - PVC: csi-sfsturbo    │
        │ - NPU 资源类: npu-2/4/8/16     │     │ - NPU 资源类: npu-1/2/4/8│
        └───────────────────────┘               └───────────────────────┘
```

## 二、对接流程概览

### 申请方（项目方）需要做的事情

| 序号 | 任务 | 说明 | 产出物 |
|:---:|------|------|--------|
| 1 | 提供项目基本信息 | 项目名称、Git 仓库地址、CI 任务描述 | 项目信息文档 |
| 2 | 创建/提供 Buildkite Agent Token | 在 Buildkite 中创建 Agent Token | Agent Token |
| 3 | 编写 pipeline.yml | 定义 CI 任务流程 | `.buildkite/pipeline.yml` |
| 4 | 提供镜像信息 | 镜像名称、推送仓库、基础镜像 | 镜像配置 |
| 5 | 确认资源需求 | NPU 卡数、内存、CPU | 资源需求清单 |

### 平台提供方需要做的事情

| 序号 | 任务 | 说明 | 产出物 |
|:---:|------|------|--------|
| 1 | 创建 ArgoCD Application | 指向部署配置的 ArgoCD 应用 | ArgoCD 配置 YAML |
| 2 | 创建 Kubernetes 资源 | Namespace、ServiceAccount、RBAC | K8s 资源 YAML |
| 3 | 创建 PVC 存储 | SFS Turbo 持久化存储 | PVC 配置 |
| 4 | 配置 values.yaml | Helm Chart 配置（队列、资源类等） | values.yaml |
| 5 | 创建 Buildkite Token Secret | 存储 Agent Token | SecretDefinition |

## 三、详细对接步骤

### 3.1 申请方：准备阶段

#### 3.1.1 提供项目基本信息

请提供以下信息：

```
项目名称: <your-project-name>
Git 仓库: https://github.com/<org>/<repo>
CI 任务描述: <描述需要运行的测试任务>
```

示例：
```
项目名称: vllm-omni
Git 仓库: https://github.com/vllm-project/vllm-omni
CI 任务描述: NPU 单元测试、构建镜像
```

#### 3.1.2 创建 Buildkite Agent Token

1. 登录 Buildkite 管理后台
2. 进入 **Agents** -> **Agent Tokens**
3. 点击 **New Token**
4. 填写描述信息（如 `vllm-omni-cn12-001`）
5. **保存生成的 Token**（只会显示一次）

**Token 命名规范**: `<project>_<cluster>`

示例：
- `vllm_project_vllm_omni_buildkite_cn12_001`
- `vllm_project_vllm_omni_buildkite_hk001`

#### 3.1.3 编写 pipeline.yml

在项目根目录创建 `.buildkite/pipeline.yml`：

```yaml
steps:
  - label: ":buildkit: Build and Push NPU Test Image"
    key: image-build
    agents:
      queue: "linux-aarch64-a2b3-gy006-test"  # 使用构建专用队列
    env:
      VLLM_IMAGE_TAG: "${BUILDKITE_COMMIT}"
      IMAGE_NAME: "vllm-omni-ci-npu"
      IMAGE_REGISTRY: "swr.cn-southwest-2.myhuaweicloud.com/modelfoundry"
      BUILDKITD_ADDR: "tcp://buildkitd-service.buildkitd:1234"
      BUILDKIT_CACHE_DIR: "/mnt/buildkit-cache"
    command: |
      set -ex
      echo "--- Building and pushing NPU Test Image"
      # ... 构建命令

  - label: "🧪 NPU Unit Test"
    depends_on: image-build
    agents:
      queue: "ascend-a3"  # 部署后的运行队列
      resource_class: npu-2  # 资源类：npu-2/npu-4/npu-8 等
    image: "${IMAGE_REGISTRY}/${IMAGE_NAME}:${BUILDKITE_COMMIT}"
    command: |
      set -ex
      echo "--- Running tests"
      pytest -v -s -m 'npu'
```

**关键配置说明**：

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `queue` | Buildkite 队列名称 | `ascend-a3`, `ascend-a2b3` |
| `resource_class` | NPU 资源类 | `npu-1`, `npu-2`, `npu-4`, `npu-8`, `npu-16` |
| `image` | 运行时使用的镜像 | `${IMAGE_REGISTRY}/${IMAGE_NAME}:${BUILDKITE_COMMIT}` |

#### 3.1.4 提供镜像信息

| 配置项 | 说明 | 示例值 |
|--------|------|--------|
| `IMAGE_NAME` | 镜像名称 | `vllm-omni-ci-npu` |
| `IMAGE_REGISTRY` | 镜像仓库地址 | `swr.cn-southwest-2.myhuaweicloud.com/modelfoundry` |
| `基础镜像` | NPU 基础镜像 | 华为官方 NPU 镜像 |

#### 3.1.5 确认资源需求

| 资源类 | NPU 卡数 | CPU | 内存 | 适用场景 |
|--------|----------|-----|------|----------|
| `npu-1` | 1 卡 | 23 核 | 64Gi | 轻量测试 |
| `npu-2` | 2 卡 | 39 核 | 128Gi | 标准测试（默认） |
| `npu-4` | 4 卡 | 78 核 | 256Gi | 中等测试 |
| `npu-8` | 8 卡 | 156 核 | 512Gi | 大型测试 |
| `npu-16` | 16 卡 | 312 核 | 1024Gi | 压测/完整测试 |

---

### 3.2 平台提供方：部署阶段

#### 3.2.1 创建 ArgoCD Application 配置

在 `ascend-ci-argocd` 仓库中创建配置：

**文件位置**：
```
applications/argocd/<cluster>/<project>-<repo>-<arch>.yaml
```

**示例（CN12-001 集群）**：

```yaml
# cn12-001/vllm-project-vllm-omni-linux-aarch64-a3.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vllm-project-vllm-omni-cn12-001-config
  namespace: argocd
spec:
  destination:
    namespace: vllm-project
    name: ascend-cn12-001-cluster
  project: ascend-cn12-001-cluster
  source:
    path: vllm-project/vllm-omni/config-cn12-001
    repoURL: https://github.com/opensourceways/ascend-ci-deployment.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
    syncOptions:
      - CreateNamespace=true

---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: vllm-project-vllm-omni-linux-aarch64-a3
  namespace: argocd
spec:
  destination:
    namespace: vllm-project
    name: ascend-cn12-001-cluster
  project: ascend-cn12-001-cluster
  source:
    helm:
      releaseName: linux-aarch64-a3
    path: vllm-project/vllm-omni/linux-aarch64-a3
    repoURL: https://github.com/opensourceways/ascend-ci-deployment.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
    syncOptions:
      - CreateNamespace=true
```

#### 3.2.2 创建部署配置目录

在 `ascend-ci-deployment` 仓库中创建：

```
vllm-project/<repo>/config-<cluster>/
vllm-project/<repo>/<arch>/
```

**目录结构**：
```
vllm-project/vllm-omni/
├── config-cn12-001/          # CN12-001 配置
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── buildkite-token-secret.yaml
│   ├── runner-pod-permission.yaml
│   └── local-storage-pvc.yaml
├── config-hk001/             # HK-001 配置
│   ├── kustomization.yaml
│   ├── buildkite-token-secret.yaml
│   └── ...
├── linux-aarch64-a3/         # A3 Helm Chart
│   ├── Chart.yaml
│   └── values.yaml
└── linux-aarch64-a2b3/       # A2B3 Helm Chart
    ├── Chart.yaml
    └── values.yaml
```

#### 3.2.3 创建 namespace.yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    app: <project-name>
  name: <project-name>
```

#### 3.2.4 创建 buildkite-token-secret.yaml

**注意**：Token 存放在 Vault 中，通过 SecretDefinition 引用。

```yaml
apiVersion: secrets-manager.tuenti.io/v1alpha1
kind: SecretDefinition
metadata:
  name: buildkite-token-secret
  namespace: <project-name>
spec:
  name: <project-buildkite-agent-token>
  keysMap:
    BUILDKITE_AGENT_TOKEN:
      path: secrets/data/ascend/ci
      key: <vault_key>
```

#### 3.2.5 创建 runner-pod-permission.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: runner-service-account
  namespace: <project-name>
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: runner-role
  namespace: <project-name>
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "create", "delete"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["get", "create"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "create", "delete"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: runner-rolebinding
  namespace: <project-name>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: runner-role
subjects:
  - kind: ServiceAccount
    name: runner-service-account
    namespace: <project-name>
```

#### 3.2.6 创建 local-storage-pvc.yaml

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <project>-<cluster>
  namespace: <project-name>
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: <size>Gi
  storageClassName: sfsturbo-subpath-sc
```

#### 3.2.7 创建 values.yaml（Helm Chart 配置）

**核心配置项**：

```yaml
agent-stack-k8s:
  agentStackSecret: <project-buildkite-agent-token>

  # Controller 资源配置
  resources:
    requests:
      cpu: "1"
      memory: "1Gi"
    limits:
      cpu: "4"
      memory: "4Gi"

  # 环境变量配置
  agentEnv:
    - name: GIT_URL
      value: "https://gh-proxy.test.osinfra.cn/https://github.com"
    - name: GIT_TERMINAL_PROMPT
      value: "0"

  nodeSelector:
    kubernetes.io/arch: amd64

  config:
    queue: <queue-name>           # 如 ascend-a3, ascend-a2b3
    max-in-flight: 10
    job-ttl: 10m
    pod-pending-timeout: 30m
    job-active-deadline-seconds: 21600

    # 资源类配置
    resource-classes:
      npu-1:
        resource:
          requests:
            cpu: "23"
            memory: "64Gi"
            huawei.com/ascend-1980: "1"
          limits:
            cpu: "23"
            memory: "64Gi"
            huawei.com/ascend-1980: "1"
      npu-2:
        resource:
          requests:
            cpu: "46"
            memory: "128Gi"
            huawei.com/ascend-1980: "2"
          limits:
            cpu: "46"
            memory: "128Gi"
            huawei.com/ascend-1980: "2"
      # ... 其他资源类

    # Pod 配置
    pod-spec-patch:
      schedulerName: volcano
      serviceAccountName: runner-service-account
      nodeSelector:
        kubernetes.io/arch: arm64
      imagePullSecrets:
        - name: huawei-swr-image-pull-secret-model-gy
      containers:
        - name: container-0
          env:
            - name: PIP_CACHE_DIR
              value: /root/.cache/pip-cache
            - name: HF_HOME
              value: /root/.cache/huggingface
            - name: TORCH_HOME
              value: /root/.cache/torch
          volumeMounts:
            - name: shared-volume
              mountPath: /root/.cache
            - name: driver-tools
              mountPath: /usr/local/Ascend/driver
              readOnly: true
            - name: shm-volume
              mountPath: /dev/shm
      volumes:
        - name: shm-volume
          emptyDir:
            medium: Memory
            sizeLimit: "16Gi"
        - name: shared-volume
          persistentVolumeClaim:
            claimName: <project>-<cluster>
        - name: driver-tools
          hostPath:
            path: /usr/local/Ascend/driver
```

#### 3.2.8 创建 kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- local-storage-pvc.yaml
- buildkite-token-secret.yaml
- namespace.yaml
- runner-pod-permission.yaml

commonAnnotations:
  kubernetes.ops.cluster: <cluster-name>
  kubernetes.ops.email: ""
  kubernetes.ops.os.base: debian
  kubernetes.ops.region: <region>
```

---

## 四、配置清单汇总

### 4.1 申请方需要提供的配置

| 配置项 | 必填 | 说明 | 示例值 |
|--------|:---:|------|--------|
| `project_name` | ✅ | 项目名称 | `vllm-omni` |
| `git_repo_url` | ✅ | Git 仓库地址 | `https://github.com/vllm-project/vllm-omni` |
| `buildkite_token` | ✅ | Buildkite Agent Token | `xxxx-xxxx-xxxx-xxxx` |
| `image_name` | ✅ | 镜像名称 | `vllm-omni-ci-npu` |
| `image_registry` | ✅ | 镜像仓库 | `swr.cn-southwest-2.myhuaweicloud.com/modelfoundry` |
| `target_cluster` | ✅ | 目标集群 | `cn12-001` 或 `hk-001` |
| `npu_type` | ✅ | NPU 类型 | `a3` (910A3) 或 `a2b3` (910A2B3) |
| `resource_class` | ✅ | 资源类 | `npu-2` |
| `pvc_size` | ✅ | 存储大小 (Gi) | `1200` |
| `pipeline_yml` | ✅ | CI 流水线配置 | `.buildkite/pipeline.yml` |

### 4.2 平台提供方需要提供的配置

| 配置项 | 说明 | 示例值 |
|--------|------|--------|
| `cluster_name` | 集群名称 | `ascend-cn12-001-cluster`, `ascend-hk-001-cluster` |
| `namespace` | Kubernetes 命名空间 | `vllm-project` |
| `queue_name` | Buildkite 队列名 | `ascend-a3`, `ascend-a2b3` |
| `vault_path` | Vault 中的 Token 路径 | `secrets/data/ascend/ci` |
| `vault_key` | Vault 中的 Token Key | `vllm_project_vllm_omni_buildkite_cn12_001` |
| `storage_class` | 存储类 | `sfsturbo-subpath-sc` |
| `image_pull_secret` | 镜像拉取 Secret | `huawei-swr-image-pull-secret-model-gy` |
| `scheduler` | 调度器 | `volcano` |
| `github_proxy` | GitHub 代理 | `https://gh-proxy.test.osinfra.cn/https://github.com` |
| `pypi_cache` | PyPI 缓存服务 | `cache-service.nginx-pypi-cache.svc.cluster.local` |

---

## 五、两个集群的配置差异

| 配置项 | CN12-001 (A3) | HK-001 (A2B3) |
|--------|---------------|---------------|
| NPU 型号 | Ascend 910A3 | Ascend 910A2B3 |
| NPU 标签 | `huawei.com/ascend-910-3` | `huawei.com/ascend-1980` |
| 队列名称 | `ascend-a3` | `ascend-a2b3` |
| 支持资源类 | npu-2, npu-4, npu-8, npu-16 | npu-1, npu-2, npu-4, npu-8 |
| 2卡 CPU | 39 核 | 46 核 |
| 2卡 内存 | 128Gi | 128Gi |
| 架构 | arm64 | arm64 |
| Pipeline 配置 | `linux-aarch64-a3` | `linux-aarch64-a2b3` |

---

## 六、常见问题

### Q1: 如何确认 Token 已经正确配置？

```bash
# 在 ArgoCD 中查看 Application 状态
argocd app get <application-name>

# 在集群中查看 Secret
kubectl get secretdefinition <project>-buildkite-token-secret -n <namespace>
```

### Q2: 如何调整资源类？

修改 `values.yaml` 中的 `resource-classes` 配置，然后提交更改。ArgoCD 会自动同步。

### Q3: 构建任务在哪里运行？

构建任务使用单独的队列（如 `linux-aarch64-a2b3-gy006-test`），不在目标集群运行，只负责构建和推送镜像。

### Q4: 如何查看 Buildkite Agent 日志？

```bash
kubectl get pods -n <namespace> -l app=agent-stack-k8s
kubectl logs <agent-pod-name> -n <namespace>
```

### Q5: 镜像构建失败怎么办？

1. 检查 buildkitd 服务是否正常运行
2. 检查 Token 权限
3. 查看构建日志确认错误信息

---

## 七、联系信息

如有疑问，请联系 CI 平台维护团队。

---

*文档版本: v1.0*
*最后更新: 2026-04-23*
