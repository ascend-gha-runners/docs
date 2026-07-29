# BuildKit 部署运维文档

> 面向 infra/DevOps 团队。涵盖 buildkitd server、ARC runner、配置模板的全流程部署。

## 目录

1. [架构概览](#1-架构概览)
2. [部署 buildkitd server](#2-部署-buildkitd-server)
3. [部署 fuse device plugin](#3-部署-fuse-device-plugin)
4. [部署 ARC runner scale set](#4-部署-arc-runner-scale-set)
5. [部署 runner pod template (ConfigMap)](#5-部署-runner-pod-template-configmap)
6. [预装 docker CLI 到共享 PVC](#6-预装-docker-cli-到共享-pvc)
7. [ArgoCD 集成](#7-argocd-集成)
8. [新集群接入清单](#8-新集群接入清单)
9. [模板化部署指南](#9-模板化部署指南)

## 1. 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                        K8s Cluster                              │
│                                                                 │
│  ┌─ buildkitd namespace ──────────────────────────────────────┐ │
│  │  buildkitd-{arch}-service :1234 (ClusterIP)                │ │
│  │    │  replica: 3, fuse-overlayfs, rootless, mTLS           │ │
│  │    │  Vault certs at /certs/ca.pem, cert.pem, key.pem      │ │
│  │    │  Proxy: Squid → external network                       │ │
│  │    └── buildkitd-{arch}-deployment                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─ buildkitd → Squid → SWR (镜像推送瓶颈) ─────────────────┐ │
│  │  30GB CANN 镜像经 Squid SSL 加解密 + 公网出口 → 占 2/5 总时间  │ │
│  │  SWR 在集群内无 VPC 直连通路，Squid 是唯一出口              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─ nv-action namespace ─────────────────────────────────────┐ │
│  │  Runner Pod (ARC scale-set)                                │ │
│  │    │  Container "runner": gha-runner listener              │ │
│  │    │  Container "$job": CI 工作容器                         │ │
│  │    │    postStart: 安装 buildctl + docker buildx setup    │ │
│  │    │    env: BUILDKITD_ADDR, DOCKER_CONFIG, proxy          │ │
│  │    │  Volumes: shared PVC, work (emptydir), pod-templates   │ │
│  │    └── ConfigMap: linux-{arch}-cpu-4-buildkit               │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌─ generic-device-plugin (daemonset) ────────────────────────┐ │
│  │  暴露 /dev/fuse 为可调度资源 devic.es/fuse                  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## 2. 部署 buildkitd server

### 2.1 组件说明

| 组件 | 作用 | 关键参数 |
|------|------|---------|
| buildkitd Deployment | 执行镜像构建的后端 | rootless, fuse-overlayfs, mTLS, 3 replica |
| buildkitd Service | ClusterIP:1234 | Runner 通过此 Service 连接 |

### 2.2 部署文件

参考文件（模板）：
- `argocd/clusters/buildkit-server/values-guiyang-006-amd64.yaml`
- `argocd/clusters/buildkit-server/values-guiyang-006-arm64.yaml`

### 2.3 关键配置项（需按集群修改）

```yaml
# 命名空间（需预先创建）
namespace: buildkitd

buildkitd:
  # 架构区分
  appName: buildkitd-{arch}       # amd64 / arm64
  
  # 副本数（按并发需求调整）
  replicaCount: 3                  # 建议 2-4
  
  # 并行度
  config:
    maxParallelism: 4              # 每个副本最大并行步骤数
    gcPolicies:
      - keepDuration: 24h          # 24h 内缓存不删
        keepBytes: 50GB            # 最小保留缓存
        maxUsedSpace: "100GB"      # 缓存上限（对应 emptyDir 磁盘）
  
  # 持久化（不能用 NFS/SFS Turbo — rootless user namespace 不支持 chown）
  # 原因：buildkitd 以 uid=1000 运行，user_namespaces(7) 映射容器内 root → 宿主机 uid=1000。
  # NFS 协议不支持在 user namespace 内执行 chown 操作，会返回 EINVAL。
  # 本地磁盘（ext4/xfs）支持此操作，因此只能用 emptyDir 或本地 PVC。
  persistence:
    enabled: false                 # 始终 false
    path: "/buildkitd-cache-{arch}"  # 固定模板: /buildkitd-cache-{arch}
    sfsturboShareId: "01d769be-xxx"  # 仅后续使用，当前不可用
  
  # 节点选择
  nodeSelector:
    kubernetes.io/arch: {arch}     # amd64 / arm64
  
  # 反亲和性（副本分散到不同节点）
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: server
                operator: In
                values: [buildkitd]
          topologyKey: kubernetes.io/hostname
  
  # Vault 证书注入（Vault 路径按集群配置）
  podAnnotations:
    vault.hashicorp.com/role: 'buildkitd'                       # Vault role
    vault.hashicorp.com/agent-inject-secret-ca.pem: 'internal/data/ascend/buildkitd'  # Vault secret path
  
  # Squid 代理
  env:
    - name: HTTP_PROXY
      value: "http://squid-cache.squid.svc.cluster.local:3128"  # 按集群调整
    - name: NO_PROXY
      value: "localhost,127.0.0.1,.svc.cluster.local,.cluster.local"
```

### 2.4 部署清单

```
argocd/clusters/buildkit-server/
├── Chart.yaml                      # Helm chart 定义（固定）
├── values.yaml                     # 默认值（固定）
├── values-guiyang-006-amd64.yaml   # gy-006 集群 amd64 配置
└── values-guiyang-006-arm64.yaml   # gy-006 集群 arm64 配置
```

## 3. 部署 fuse device plugin

### 3.1 组件说明

buildkitd rootless 模式需要 fuse-overlayfs snapshotter，依赖 `/dev/fuse` 设备。通过 `generic-device-plugin` daemonset 暴露 `/dev/fuse` 为 K8s 资源。

### 3.2 部署文件

参考文件：`argocd/clusters/gy-006/generic-device-plugin.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: generic-device-plugin
  namespace: argocd
spec:
  destination:
    namespace: kube-system
    name: {cluster-name}               # ← 按集群修改
  project: {project-name}              # ← 按集群修改
  source:
    path: manifests/generic-device-plugin
    repoURL: https://github.com/opensourceways/ascend-ci-deployment.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
```

### 3.3 插件清单

```
manifests/generic-device-plugin/
├── generic-device-plugin.yaml        # DaemonSet (暴露 /dev/fuse)
├── kustomization.yaml                # Kustomize 配置
└── resource.yaml                     # device plugin 资源注册
```

## 4. 部署 ARC runner scale set

### 4.1 组件说明

| 组件 | 作用 | 关键配置 |
|------|------|---------|
| Runner Scale Set (Helm) | ARC 管理的 runner 组 | githubConfigUrl, containerMode, podTemplate |
| Runner Pod | 执行 CI job 的工作节点 | 4c8g, shared PVC, pod-template ConfigMap |

### 4.2 部署文件（模板）

参考文件：
- `other/nv-action/vllm-benchmarks/linux-aarch64-cpu-4-buildkit-gy006/`
- `other/nv-action/vllm-benchmarks/linux-amd64-cpu-4-buildkit-gy006/`

每架构一个目录，包含 `Chart.yaml` 和 `values.yaml`。

### 4.3 关键配置项（需按项目/集群修改）

```yaml
# values.yaml 模板
gha-runner-scale-set:

  # ═══ 必须修改 ═══
  githubConfigUrl: https://github.com/{org}/{repo}              # ← 目标仓库
  githubConfigSecret: {repo}-secret                             # ← GitHub App/Token Secret
  
  scaleSetLabels:
    - "linux-{arch}-cpu-{cores}-buildkit"                       # ← 自定义 runner 标签
    - "{cluster-label}"                                         # ← 集群标识

  containerMode:
    type: "kubernetes-novolume"                                 # 固定

  # ═══ 监听器配置（固定）═══
  listenerTemplate:
    spec:
      containers:
        - name: listener
          image: swr.cn-southwest-2.myhuaweicloud.com/modelfoundry/gha-runner-scale-set-controller:0.14.201
      nodeSelector:
        kubernetes.io/arch: amd64                               # 监听器只跑在 amd64

  # ═══ Runner Pod 配置 ═══
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: {arch}                              # ← amd64 / arm64
      
      containers:
        - name: runner
          image: swr.cn-southwest-2.myhuaweicloud.com/modelfoundry/runner-containers-hooks:release-no_volumes-b9cff6
          command: ["/home/runner/run.sh"]
          env:
            - name: ACTIONS_RUNNER_CONTAINER_HOOK_TEMPLATE
              value: /home/runner/pod-templates/default.yaml   # 指向 pod template ConfigMap
            # ... 其他固定配置 ...
          volumeMounts:
            - name: pod-templates
              mountPath: /home/runner/pod-templates
              readOnly: true
            - name: shared-volume
              mountPath: /root/.cache                          # 共享缓存 PVC

      volumes:
        - name: pod-templates
          configMap:
            name: linux-{arch}-cpu-{cores}-buildkit             # ← 架构 ConfigMap
        - name: shared-volume
          persistentVolumeClaim:
            claimName: {project}-pvc-name                       # ← 项目 PVC
```

### 4.4 命名规范

```
目录名: linux-{arch}-cpu-{cores}-buildkit-{cluster}
Runner 标签: ["linux-{arch}-cpu-{cores}-buildkit", "{cluster}"]
ConfigMap 名: linux-{arch}-cpu-{cores}-buildkit
```

## 5. 部署 runner pod template (ConfigMap)

### 5.1 组件说明

Pod Template ConfigMap 定义 CI job 容器的运行时配置：PATH、环境变量、volume mounts、postStart 生命周期钩子。

### 5.2 部署文件（模板）

参考文件：
- `other/nv-action/vllm-benchmarks/config-for-guiyang-006/linux-amd64-cpu-4-buildkit-configmap.yaml`
- `other/nv-action/vllm-benchmarks/config-for-guiyang-006/linux-aarch64-cpu-4-buildkit-configmap.yaml`

### 5.3 关键配置项（需按项目/集群修改）

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: linux-{arch}-cpu-4-buildkit     # ← 与 runner values 中 pod-templates configMap 名一致
  namespace: {project-namespace}        # ← 项目命名空间

data:
  default.yaml: |
    spec:
      nodeSelector:
        beta.kubernetes.io/arch: {arch}               # ← amd64 / arm64

      serviceAccount: runner-service-account

      containers:
        - name: $job
          resources:
            limits:   {cpu: "4", memory: 8Gi}         # 根据任务调整
            requests: {cpu: "4", memory: 8Gi}

          env:
            # ═══ 必须修改 ═══
            - name: BUILDKITD_ADDR
              value: "tcp://buildkitd-{arch}-service.buildkitd:1234"   # ← buildkitd Service
            - name: DOCKER_CONFIG
              value: "/home/user/.docker"                              # 固定
            - name: PATH
              value: "/root/.cache/buildkit/bin/{arch}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"  # ← 架构路径

            # ═══ 按集群修改 ═══
            - name: HTTP_PROXY
              value: "http://squid-cache.squid.svc.cluster.local:3128" # ← squid 地址
            - name: NO_PROXY
              value: "localhost,127.0.0.1,.svc.cluster.local,.cluster.local"

          # postStart 自动脚本（固定，不需要修改）
          lifecycle:
            postStart:
              exec:
                command:
                  - /bin/sh
                  - -c
                  - |
                    set -ex
                    # 1. 等待 Vault 证书（30s 超时）
                    # 2. 安装 buildctl 到共享 PVC
                    # 3. 复制 buildx 插件到 DOCKER_CONFIG
                    # 4. 创建 docker buildx remote builder

      volumes:
        - name: shared-volume
          persistentVolumeClaim:
            claimName: {project}-pvc-name               # ← 项目 PVC
        - name: squid-ca
          configMap:
            name: squid-ca-cert
            optional: true
```

### 5.4 架构差异

| 参数 | amd64 | arm64 |
|------|-------|-------|
| BUILDKITD_ADDR | `buildkitd-amd64-service.buildkitd:1234` | `buildkitd-arm64-service.buildkitd:1234` |
| PATH 前缀 | `/root/.cache/buildkit/bin/amd64` | `/root/.cache/buildkit/bin/arm64` |
| nodeSelector.arch | `amd64` | `arm64` |
| nodeSelector.beta | `beta.kubernetes.io/arch: amd64` | `beta.kubernetes.io/arch: arm64` |

## 6. 预装 docker CLI 到共享 PVC

### 6.1 组件说明

docker CLI + buildx 插件需预先安装到共享 PVC（一次性 Job）。runner pod template 中 postStart 脚本会自动复用缓存。

### 6.2 部署文件（模板）

参考文件：
- `other/nv-action/vllm-benchmarks/config-for-guiyang-006/install-docker-cli-amd64.yaml`
- `other/nv-action/vllm-benchmarks/config-for-guiyang-006/install-docker-cli-arm64.yaml`

### 6.3 关键配置项（需按项目/集群修改）

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: install-docker-cli-{arch}         # ← amd64 / arm64
  namespace: {project-namespace}           # ← 项目命名空间
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: {arch}         # ← amd64 / arm64

      volumes:
        - name: cache
          persistentVolumeClaim:
            claimName: {project}-pvc-name  # ← 项目 PVC

      containers:
        - name: installer
          image: {your-base-image}         # ← 任意 Ubuntu 22.04 镜像
          env:
            - name: HTTP_PROXY
              value: "http://squid-cache.squid.svc.cluster.local:3128"  # ← squid 地址
          volumeMounts:
            - name: cache
              mountPath: /root/.cache
          command:
            - bash
            - -c
            - |
              set -e
              ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
              MIRROR="https://repo.huaweicloud.com/docker-ce/linux/ubuntu/dists/jammy/pool/stable/${ARCH}"
              CACHE="/root/.cache/buildkit/bin/${ARCH}"
              mkdir -p "$CACHE/cli-plugins"

              # 安装 docker CLI
              curl -fsSLk --max-time 300 "${MIRROR}/docker-ce-cli_29.6.2-1~ubuntu.22.04~jammy_${ARCH}.deb" -o /tmp/docker.deb
              dpkg-deb -x /tmp/docker.deb /tmp/de
              cp /tmp/de/usr/bin/docker "$CACHE/docker"
              chmod +x "$CACHE/docker"

              # 安装 buildx 插件
              curl -fsSLk --max-time 300 "${MIRROR}/docker-buildx-plugin_0.11.2-1~ubuntu.22.04~jammy_${ARCH}.deb" -o /tmp/bx.deb
              dpkg-deb -x /tmp/bx.deb /tmp/bx
              cp /tmp/bx/usr/libexec/docker/cli-plugins/docker-buildx "$CACHE/cli-plugins/docker-buildx"
              chmod +x "$CACHE/cli-plugins/docker-buildx"

              export PATH="$CACHE:$PATH"
              docker --version
              docker buildx version
              echo "=== DONE ==="
```

### 6.4 注意事项

- **先于 runner 部署**：在 runner scale set 创建前运行 Job
- **一次性操作**：Job 成功后 docker 永久存在于 PVC
- **架构区分**：两个 Job 分别跑在 amd64/arm64 节点上
- **版本管理**：docker CLI v29.6.2, buildx v0.11.2（从 huaweicloud mirror 下载）

## 7. ArgoCD 集成

### 7.1 Application 清单

所有组件均通过 ArgoCD 管理。gy-006 集群示例：

| Application | 路径 | 同步内容 |
|-------------|------|---------|
| `buildkitd-server-gy006-amd64` | `argocd/clusters/buildkit-server/values-guiyang-006-amd64.yaml` | buildkitd Helm chart (amd64) |
| `buildkitd-server-gy006-arm64` | `argocd/clusters/buildkit-server/values-guiyang-006-arm64.yaml` | buildkitd Helm chart (arm64) |
| `nv-action-vllm-benchmarks-config-gy006` | `other/nv-action/vllm-benchmarks/config-for-guiyang-006/` | ConfigMaps + Jobs |
| `nv-action-vllm-benchmarks-gy006-*-buildkit` | `other/nv-action/vllm-benchmarks/linux-{arch}-cpu-4-buildkit-gy006/` | ARC runner scale set |

### 7.2 同步策略

```yaml
syncPolicy:
  automated:
    prune: true
  syncOptions:
    - CreateNamespace=true
```

### 7.3 文件组织建议

```
repo-root/
├── argocd/
│   └── clusters/
│       ├── {cluster}/
│       │   ├── generic-device-plugin.yaml              # 全局 DaemonSet
│       │   ├── buildkitd-server-amd64.yaml             # buildkitd amd64
│       │   ├── buildkitd-server-arm64.yaml             # buildkitd arm64
│       │   └── {project}-buildkit-runner-{arch}.yaml   # runner scale set
│       └── buildkit-server/
│           ├── values-{cluster}-amd64.yaml             # buildkitd values
│           └── values-{cluster}-arm64.yaml
└── other/
    └── {project}/
        └── config-for-{cluster}/                       # ConfigMaps + Jobs
            ├── linux-amd64-cpu-{cores}-buildkit-configmap.yaml
            ├── linux-aarch64-cpu-{cores}-buildkit-configmap.yaml
            ├── install-docker-cli-amd64.yaml
            └── install-docker-cli-arm64.yaml
```

## 8. 新集群接入清单

### 8.1 前置条件

| 检查项 | 说明 |
|--------|------|
| ✅ K8s 集群已部署 | 有 amd64 + arm64 节点 |
| ✅ Vault 已配置 | `internal/data/ascend/buildkitd` 路径存在 |
| ✅ Squid proxy 已部署 | HTTP/HTTPS 代理可用 |
| ✅ nginx-pypi-cache 已部署 | pip/apt/PyTorch 代理可用 |
| ✅ SWR 镜像仓库 | 有 docker config secret |
| ✅ ArgoCD 已部署 | 管理所有 K8s 资源 |
| ✅ GitHub App 已安装 | 仓库有 self-hosted runner 权限 |

### 8.2 部署步骤

```
1. 部署 generic-device-plugin (DaemonSet)
   → kubectl apply 或 ArgoCD Application

2. 部署 buildkitd server (每架构)
   → 复制 values-{cluster}-{arch}.yaml，修改 appName 等
   → 创建 ArgoCD Application

3. 创建命名空间 + PVC + ServiceAccount
   → kubectl create ns {project}
   → kubectl apply -f pvc.yaml serviceaccount.yaml

4. 预装 docker CLI 到 PVC (Job)
   → kubectl apply -f install-docker-cli-amd64.yaml
   → kubectl apply -f install-docker-cli-arm64.yaml
   → 等待 Job 完成

5. 部署 runner pod template (ConfigMap)
   → 复制 configmap 模板，修改 PROJECT、ARCH、PVC 等

6. 部署 runner scale set (每架构)
   → 复制 values.yaml 模板，修改 githubConfigUrl、labels 等
   → 创建 ArgoCD Application

7. 验证
   → kubectl get pods -n {project}  # 确认 runner 在运行
   → 在 GitHub 仓库触发 CI 验证
```

### 8.3 验证命令

```bash
# 检查 buildkitd
kubectl -n buildkitd get pods,svc

# 检查 runner
kubectl -n {project} get pods
kubectl -n {project} logs {runner-pod} -c runner

# 检查 docker CLI
kubectl -n {project} get jobs | grep install-docker

# 检查 PVC
kubectl -n {project} get pvc
kubectl -n {project} exec {runner-pod} -c runner -- ls -la /root/.cache/buildkit/bin/*/docker
```

## 9. 模板化部署指南

### 9.1 变量替换清单

| 变量 | 示例值 | 说明 |
|------|--------|------|
| `{cluster}` | `gy-006`, `hk-001` | 集群标识 |
| `{arch}` | `amd64`, `arm64` | CPU 架构 |
| `{cores}` | `4` | Runner CPU cores |
| `{project}` | `nv-action-vllm-benchmarks` | 项目名（GitHub repo） |
| `{org}` | `nv-action` | GitHub org |
| `{repo}` | `vllm-benchmarks` | GitHub repo 名 |
| `{project-namespace}` | `nv-action` | K8s 命名空间 |
| `{project-pvc-name}` | `nv-action-vllm-benchmarks-gy006` | 共享 PVC 名称 |
| `{squid-url}` | `http://squid-cache.squid.svc.cluster.local:3128` | Squid 代理地址 |
| `{vault-path}` | `internal/data/ascend/buildkitd` | Vault secret 路径 |
| `{base-image}` | `swr.cn-xxx.myhuaweicloud.com/cann:9.0.0` | 基础镜像 |

### 9.2 快速启动脚本

```bash
#!/bin/bash
# 新集群 buildkit 部署脚本
# Usage: ./deploy-buildkit.sh --cluster gy-006 --arch amd64 --project my-project

CLUSTER="${CLUSTER:-gy-006}"
ARCH="${ARCH:-amd64}"
PROJECT="${PROJECT:-my-project}"
NAMESPACE="${NAMESPACE:-my-project}"
CORES="${CORES:-4}"

# 1. 部署 generic-device-plugin（如未部署）
# kubectl apply -f argocd/clusters/${CLUSTER}/generic-device-plugin.yaml

# 2. 创建命名空间 + PVC
kubectl create ns ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PROJECT}-${CLUSTER}
  namespace: ${NAMESPACE}
spec:
  accessModes: [ReadWriteMany]
  storageClassName: sfsturbo-subpath-sc
  resources:
    requests:
      storage: 64Gi
EOF

# 3. 预装 docker CLI
kubectl apply -f install-docker-cli-${ARCH}.yaml

# 4. 部署 runner configmap 和 scale set
# helm install ... 或 ArgoCD Application
```

### 9.3 Vault 配置模板

```hcl
# Vault secret 路径: internal/data/ascend/buildkitd
{
  "RootCA": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "ServerCaCert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "ServerCaKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",
  "ClientCaCert": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "ClientCaKey": "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",
  "dockerConfig": "{\"auths\":{\"swr.cn-southwest-2.myhuaweicloud.com\":{\"auth\":\"base64-encoded-credentials\"}}}"
}
```

## 10. 性能分析

### 10.1 镜像导出为什么慢

导出（push）占镜像构建总时间的约 **2/5**，原因：

```
buildkitd Pod ──8-30GB diff 层──► Squid Pod ──SSL 加解密──► 公网出口 ──► SWR Registry
                                      ↑
                                这里是瓶颈：
                                1. 每字节 SSL 解密→检查→重新加密
                                2. 3 个 buildkitd 副本共享一个 Squid 出口
                                3. CANN 基础镜像 15-30GB，整体体量大
```

| 因素 | 影响 |
|------|------|
| CANN 基础镜像太大 | 15-30GB，即使只推 diff 层也有数 GB |
| Squid 加解密开销 | HTTPS 流量需要解密/检查/重加密 |
| 公网出口带宽 | Squid → SWR 走公网，非内网直连 |
| `buildkit-cache` tag | 每次构建输出两个 tag，多一次 manifest push |

### 10.2 已验证的优化

| 方向 | 结果 | 说明 |
|------|:---:|------|
| 加 `.myhuaweicloud.com` 到 `NO_PROXY` | ❌ 不可行 | 集群节点到 SWR 无内网直连通路 |
| 切换到 `compression: zstd` | ❌ 不建议 | 破坏已有 gzip 缓存；新层体积大 15% |
| 去掉 `buildkit-cache` tag | ❌ 不可行 | 去掉后 cache-from 无法命中最新缓存 |

### 10.3 本质原因

导出慢在当前架构下是**正常且无法绕开的**——SWR 在集群内没有内网直通，Squid 是唯一出口通道。在 VPC Endpoint 就位之前只能接受。

## 11. 已知限制与未来规划

### 11.1 当前限制

| 限制 | 原因 | 影响 |
|------|------|------|
| 导出速度 | Squid SSL 加解密 + 公网出口 | 占构建总时间 2/5 |
| 无持久化缓存 | NFS 不支持 rootless user ns chown | Pod 重启缓存丢失，用 registry cache 恢复 |
| 不支持 VPC Endpoint | 华为云专属，其他 registry 无效 | 换 Docker Hub/GHCR 等同样慢 |

### 11.2 短期方案（已落地）

- **Registry cache**：`cache-from` + `cache-to: inline`，Pod 重启后从上次推送的镜像恢复缓存
- **Docker CLI + buildx 预装**：一次性 Job 写到共享 PVC，postStart 自动复用

### 11.3 长期方向

1. **VPC Endpoint**：华为云内部直达 SWR，绕过 Squid + 公网。仅适用 SWR 场景
2. **StatefulSet + 一致性哈希**：
   - Deployment → StatefulSet，每个 Pod 挂独立本地磁盘（ext4/xfs）
   - 客户端根据项目名做一致性哈希，始终路由到同一个 Pod
   - Pod 重启 / 漂移后缓存不丢，不需要 NFS
   - 依赖 [moby/buildkit#3154](https://github.com/moby/buildkit/issues/3154) 或自建 gRPC proxy

## 12. 文件索引

| 文件 | 类型 | 说明 |
|------|------|------|
| `argocd/clusters/buildkit-server/values-{cluster}-{arch}.yaml` | 模板 | buildkitd server Helm values |
| `argocd/clusters/gy-006/generic-device-plugin.yaml` | 示例 | fuse device plugin ArgoCD App |
| `other/{project}/linux-{arch}-cpu-{cores}-buildkit-{cluster}/` | 模板 | ARC runner scale set Helm chart |
| `other/{project}/config-for-{cluster}/linux-{arch}-cpu-{cores}-buildkit-configmap.yaml` | 模板 | Pod template ConfigMap |
| `other/{project}/config-for-{cluster}/install-docker-cli-{arch}.yaml` | 模板 | Docker CLI 安装 Job |
| `manifests/generic-device-plugin/` | 固定 | fuse device plugin 资源 |
