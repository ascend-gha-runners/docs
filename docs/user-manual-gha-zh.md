# GitHub Actions 接入昇腾算力指导

> 本文档面向开源社区管理员,指导你如何将项目接入 GitHub Actions CI 系统,使用昇腾（Ascend）NPU 算力运行 CI 任务。

## 接入全景图

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                             你的项目仓库 (GitHub)                              │
│ https://github.com/<org>/<repo>                                                │
│ .github/workflows/*.yaml                                                       │
└────────────────────────┬───────────────────────────────────────────────────────┘
                         │ GitHub 事件触发
                         │ (push/PR/schedule等)
                         ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions Cloud                                     │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│   │  Workflow   │───▶│   Runner    │───▶│    Pod      │───▶│    Job      │     │
│   │  定义流程   │───▶│  Scale Set  │───▶│  执行器     │───▶│  运行任务   │     │
│   └─────────────┘    └─────────────┘    └──────┬──────┘    └─────────────┘     │
└────────────────────────────────────────────────┼───────────────────────────────┘
                                                  │ GitHub App/PAT 认证
                                                  ▼
┌────────────────────────────────────────────────────────────────────────────────┐
│                            基础设施 Kubernetes 集群                            │
│   ┌─────────────────────┐              ┌─────────────────────┐                 │
│   │  CN12-001 集群      │              │  HK-001 集群        │                 │
│   │  Ascend 910A3      │              │  Ascend 910A2B3     │                 │
│   │  runner: 310p/910c │              │ runner: arm64-npu   │                 │
│   └─────────────────────┘              └─────────────────────┘                 │
└────────────────────────────────────────────────────────────────────────────────┘
```

我们基于[ARC](https://github.com/actions/actions-runner-controller/)实现 GitHub Action 任务在昇腾集群节点上执行。

## Runner Pod 类型及命名方式

昇腾集群创建 runner pod 执行 GitHub Action job。我们提供如下类型的昇腾芯片。如果您未指定名称,我们将使用默认命名。

|类型|架构|节点数|每台节点卡数|默认命名(x表示卡数)|
|--|--|--|--|--|
|310P3|arm64|1|8|linux-aarch64-310p-x|
|910C|arm64|2|16|linux-aarch64-910c-x|
|910B4|arm64|4|8|linux-arm64-npu-x|
|910B1|arm64|4|8|linux-aarch64-a2-x|

### 默认 runner pod 命名规范

Runner pod 名称由以下部分组成：

```
linux-arm64-npu-x
^     ^     ^   ^
|     |     |   |
|     |     |   Number of NPUs Available
|     |     NPU Designator
|     Architecture
Operating System
```

## 接入流程图

```
                       开始
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 1: 选择安装范围和认证方式                        │
│ 你：确定是组织级还是仓库级安装                        │
│ 你：选择 GitHub App 或 PAT 认证                      │
│ 验收：明确安装方案                                    │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 2: 准备权限和凭证                                │
│ 你：获取组织或仓库管理权限                            │
│ 你：(可选) 创建 GitHub App 或 PAT                     │
│ 验收：权限和凭证已准备就绪                            │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 3: 安装 GitHub App 或提交 PAT                    │
│ 你：在 GitHub 安装 App 或生成 PAT                     │
│ 我们：提供安装指引                                    │
│ 验收：App 已安装或 PAT 已生成                        │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 4: 提交激活申请                                  │
│ 你：通过 Issue 或邮件提交申请                         │
│ 我们：部署和配置 Runner                               │
│ 验收：收到申请确认                                    │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 5: 验证 Runner 可用                              │
│ 你：在仓库 Settings 查看 Runner 状态                   │
│ 我们：协助排查连接问题                                │
│ 验收：Runner 状态显示 Online                          │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 6: 编写和测试 Workflow                           │
│ 你：编写使用 NPU 的 workflow 文件                     │
│ 我们：提供模板和最佳实践                              │
│ 验收：Workflow 成功在 NPU 上运行                      │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
                     完成接入
```

## 详细步骤

### 步骤 1: 选择安装范围和认证方式

**目标**：确定 Runner 的安装范围（组织级或仓库级）和认证方式（GitHub App 或 PAT）。

你需要做什么：

1. **确定安装范围**：
   - **组织级安装**：Runner 可在组织下所有仓库间复用，通过 Runner Group 控制访问权限
   - **仓库级安装**：Runner 仅对单个仓库可用
   
2. **选择认证方式**：
   - **GitHub App**（推荐）：更安全，权限控制更细粒度，但需要组织管理权限
   - **PAT (Personal Access Token)**：适合无法获取组织权限的场景，需注意 Token 有效期

对比表：

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| 组织 + GitHub App | 安全性高，权限细粒度控制 | 需要组织管理权限 | 多仓库复用，生产环境 |
| 组织 + PAT | 权限要求较低 | Token 需定期更新 | 临时测试，权限受限 |
| 仓库 + GitHub App | 无需组织权限 | 仅单仓库可用 | 单仓库项目 |
| 仓库 + PAT | 权限要求最低 | Token 需定期更新，单仓库 | 快速测试，权限受限 |

怎么验证这步完成：

- 已明确 Runner 安装范围（组织或仓库）
- 已选择合适的认证方式（GitHub App 或 PAT）
- 已确认具备相应的权限

---

### 步骤 2: 准备权限和凭证

**目标**：确保具备必要的权限，并准备好认证凭证。

你需要做什么：

#### 如果选择 GitHub App 方式：

1. **确认权限**：
   - 组织级安装：需要组织的 **Owner** 权限
   - 仓库级安装：需要组织的 **Owner** 权限 + 仓库的 **Admin** 权限

2. **安装 GitHub App**：
   - 浏览器访问 [apps/ascend-runner-mgmt](https://github.com/apps/ascend-runner-mgmt)
   - 点击 `Install`
   - 选择目标组织
   - 选择仓库范围：
     - 组织级：选择 `All repositories`
     - 仓库级：选择 `Only select repositories`，然后选择目标仓库
   - 点击 `Install`

![alt text](assets/user-manual-zh/image-3.png)

#### 如果选择 PAT 方式：

1. **创建 Personal Access Token**：
   - 访问 GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - 点击 `Generate new token (classic)`
   - 填写 Token 描述，如：`Ascend NPU Runner`
   - 选择权限范围（scopes）：
     - 组织级：选择 `admin:org`
     - 仓库级：选择 `repo`
   - 设置过期时间（建议 90 天）
   - 点击 `Generate token`
   - **立即复制保存 Token**（Token 只显示一次）

![alt text](assets/user-manual-zh/image-23.png)

2. **注意事项**：
   - Token 到期后，Runner 将无法工作，需重新生成有效 Token
   - 不要将 Token 提交到代码仓库或公开渠道

我们做什么：

- 提供详细的权限要求和 Token 创建指引
- 协助排查权限问题

怎么验证这步完成：

- GitHub App 已成功安装到目标组织或仓库
- 或 PAT 已成功创建并妥善保存

---

### 步骤 3: 提交激活申请

**目标**：向基础设施团队提交 Runner 激活申请，等待部署完成。

你需要做什么：

#### 如果选择 GitHub App 方式：

1. **提交 Issue 申请**：
   - 访问 [ascend-gha-runners/org-archive/issues](https://github.com/ascend-gha-runners/org-archive/issues)
   - 点击 `New issue`
   - 选择对应的模板：
     - 组织级：选择 `Add Or Modify Organization`
     - 仓库级：选择 `Add Or Modify Repository`

![alt text](assets/user-manual-zh/image-17.png)

2. **填写申请信息**：

   **组织级申请**需填写：
   ```
   org-name: <你的组织名称>
   runner-group-name: Default (或自定义 Runner Group 名称)
   runner-names: linux-arm64-npu-1 (或自定义 Runner 名称，多个用逗号分隔)
   ```
   
   ![alt text](assets/user-manual-zh/image-1.png)
   
   **仓库级申请**需填写：
   ```
   repo-name: <组织名/仓库名>
   runner-names: linux-arm64-npu-1 (或自定义 Runner 名称，多个用逗号分隔)
   ```
   
   ![alt text](assets/user-manual-zh/image-2.png)

3. **点击 `Create` 提交申请**

#### 如果选择 PAT 方式：

考虑到 Token 保密需求，申请方式是向 `gouzhonglin@huawei.com` 发送邮件：

1. **邮件主题**：`Request Ascend NPU Runners`

2. **邮件内容模板**：

   **组织级申请**：
   ```yaml
   repo: https://github.com/my-org/
   runner-group: ascend-ci
   token: ghp_xxx
   expire-at: 30days
   runner-names: linux-arm64-npu-1
   ```
   
   **仓库级申请**：
   ```yaml
   repo: https://github.com/my-org/my-repo
   token: ghp_xxx
   expire-at: 30days
   runner-names: linux-arm64-npu-1
   ```

3. **发送邮件后等待确认回复**

我们做什么：

- 收到申请后，在 Kubernetes 集群中部署和配置 Runner
- 配置 Runner Scale Set 并注册到 GitHub
- 验证 Runner 连接状态

怎么验证这步完成：

- GitHub App 方式：Issue 已提交，收到基础设施团队的回复确认
- PAT 方式：邮件已发送，收到确认回复

---

### 步骤 4: (可选) 配置 Runner Group

**目标**：为组织级安装配置 Runner Group，控制哪些仓库可以使用 Runner。

你需要做什么：

1. **创建 Runner Group**（如果默认 Runner Group 不满足需求）：
   - 进入组织 → `Settings` → `Actions` → `Runner groups`
   - 点击 `New runner group`
   - 填写名称，如：`ascend-ci`
   - 配置仓库访问权限：
     - `Repository access`：选择 `All repositories` 或 `Selected repositories`
     - `Visibility`：选择 `Private` 或 `Public`
   - 点击 `Create group`

2. **配置 Runner Group**：
   - Runner Group 有 3 个配置选项：
     - **仓库**：选择组织下所有仓库 / 选择指定仓库
     - **仓库访问权限**：private / public
     - **workflow**：选择所有 workflow / 选择指定 workflow
   - 同时满足 3 个配置的仓库可以使用组织的 Runner

3. **注意事项**：
   - 如果没有指定 Runner Group，则使用默认 Runner Group
   - 默认 Runner Group 配置：所有仓库 + Private + 所有 Workflow
   - 可以修改默认 Runner Group 的权限设置

怎么验证这步完成：

- Runner Group 已创建或使用默认 Runner Group
- Runner Group 的仓库访问权限配置符合预期

---

### 步骤 5: 验证 Runner 可用

**目标**：确认 Runner 已成功部署并连接到 GitHub，状态为 Online。

你需要做什么：

1. **查看 Runner 状态**：
   - 进入你的仓库 → `Settings` → `Actions` → `Runners`
   - 或进入组织 → `Settings` → `Actions` → `Runners`

2. **确认 Runner 列表**：
   - `Runner scale set`：配置到仓库的 Runner
   - `Shared with this repository`：仓库可访问的组织 Runner
   - 查看 `Status` 列：**绿色 `Online`** 表示 Runner 已连接并可用

![alt text](assets/user-manual-zh/image-24.png)

3. **如果状态不是 Online**：
   - 检查 GitHub App 是否正确安装
   - 检查 PAT 是否有效且未过期
   - 检查 Runner Group 权限配置
   - 联系基础设施团队排查

我们做什么：

- 监控 Runner 部署状态
- 协助排查连接问题
- 确认 Runner Scale Set 正常运行

怎么验证这步完成：

- 在 GitHub Settings 中能看到 Runner
- Runner 状态显示为 **Online**（绿色圆点）

---

### 步骤 6: 编写和测试 Workflow

**目标**：编写 GitHub Actions workflow 文件，正确使用 NPU Runner 执行任务。

你需要做什么：

1. **创建 workflow 文件**：
   - 在仓库根目录创建 `.github/workflows/` 目录
   - 创建 YAML 文件，如 `npu-test.yml`

2. **编写 workflow**：

**示例 workflow**：

```yaml
name: Test NPU Runner
on:
  workflow_dispatch:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test-npu:
    runs-on: linux-arm64-npu-1
    container:
      image: ascendai/cann:latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Show NPU info
        run: |
          npu-smi info
          echo "NPU is ready!"
      
      - name: Run tests
        run: |
          # 你的测试命令
          echo "Running tests on NPU..."
```

3. **关键字段说明**：

| 字段 | 含义 | 示例值 | 说明 |
|------|------|--------|------|
| `runs-on` | **Runner 标签** | `linux-arm64-npu-1` | **必填**，指定使用哪个 Runner，必须与步骤 3 申请的名称一致 |
| `container.image` | **运行镜像** | `ascendai/cann:latest` | **必填**，指定包含 NPU 驱动的容器镜像，否则 NPU 资源无法分配 |
| `container.options` | 容器选项 | `--privileged` | 可选，指定容器运行选项 |
| `steps` | 任务步骤 | 见示例 | 定义具体要执行的步骤 |

4. **资源规格选择**：

根据申请的 Runner 名称选择对应的 NPU 卡数：

| Runner 名称 | NPU 卡数 | CPU | 内存 | 适用场景 |
|-------------|----------|-----|------|----------|
| `linux-arm64-npu-1` | 1 卡 | 23 核 | 64Gi | 轻量测试 |
| `linux-arm64-npu-2` | 2 卡 | 39-46 核 | 128Gi | 标准测试（推荐） |
| `linux-arm64-npu-4` | 4 卡 | 78 核 | 256Gi | 中等规模测试 |
| `linux-arm64-npu-8` | 8 卡 | 156 核 | 512Gi | 大规模测试 |

> **注意**：如果在 `runs-on` 中指定的 Runner 不存在或状态不在线，workflow 会一直等待，直到 Runner 可用。

5. **提交并测试**：
   - 将 workflow 文件提交到仓库
   - 触发方式：
     - 手动触发：在 GitHub → Actions 页面选择 workflow 并点击 `Run workflow`
     - 自动触发：推送代码或创建 PR

我们做什么：

- 提供 workflow 模板和最佳实践
- 协助排查 workflow 运行问题
- 确认 NPU 资源正确分配

怎么验证这步完成：

- workflow 文件已提交到仓库
- workflow 成功触发并运行
- 日志中能看到 NPU 信息（`npu-smi info` 输出正常）
- 任务在 NPU 上成功执行

验证检查清单：

- [ ] 已明确安装范围（组织级或仓库级）
- [ ] 已选择认证方式（GitHub App 或 PAT）
- [ ] GitHub App 已安装或 PAT 已生成
- [ ] 激活申请已提交，收到基础设施团队确认
- [ ] Runner Group 已配置（如果需要）
- [ ] GitHub Settings 中能看到 Runner
- [ ] Runner 状态显示为 Online（绿色）
- [ ] `.github/workflows/*.yaml` 已提交到仓库
- [ ] workflow 使用正确的 `runs-on` 标签
- [ ] workflow 指定了 `container.image`
- [ ] workflow 成功触发并运行
- [ ] Job 成功在昇腾 NPU 上执行

---

## 常见问题

**Q1：如何知道我的组织是否有权限安装 GitHub App？**

需要组织的 Owner 权限。如果不确定，请联系你的组织管理员。查看方式：
- 进入组织 → `Settings` → `Members` → 查看你的角色

**Q2：Runner 状态一直是 Offline 怎么办？**

- 检查 GitHub App 是否正确安装（Settings → Applications）
- 检查 PAT 是否有效且未过期
- 确认 Runner Group 权限配置是否正确
- 联系基础设施团队排查 Runner Pod 状态

**Q3：workflow 一直在等待 Runner，无法运行？**

- 确认 `runs-on` 字段的值与申请的 Runner 名称完全一致
- 检查 Runner 状态是否为 Online
- 确认仓库有权访问该 Runner（Runner Group 配置）
- 如果使用自定义 Runner 名称，确认已在申请中说明

**Q4：workflow 运行时报错 "no space left on device"？**

- 可能是容器镜像过大或中间文件过多
- 在 workflow 中添加清理步骤：
  ```yaml
  - name: Clean up
    run: |
      docker system prune -af
      rm -rf /tmp/*
  ```

**Q5：如何使用多个 NPU 卡？**

在 `runs-on` 中指定对应卡数的 Runner 名称：
- 2 卡：`linux-arm64-npu-2`
- 4 卡：`linux-arm64-npu-4`
- 8 卡：`linux-arm64-npu-8`

**Q6：PAT 过期了怎么办？**

- 重新生成 PAT（参考步骤 2）
- 通过邮件将新 Token 发送给基础设施团队
- 等待基础设施团队更新配置

**Q7：如何在多个仓库间共享 Runner？**

- 使用组织级安装（通过 GitHub App 或 PAT 安装到组织）
- 通过 Runner Group 控制哪些仓库可以访问 Runner
- 在仓库的 workflow 中直接使用组织 Runner 的标签

**Q8：workflow 中如何使用自定义容器镜像？**

```yaml
jobs:
  test:
    runs-on: linux-arm64-npu-1
    container:
      image: your-registry/your-image:tag
      credentials:
        username: ${{ secrets.REGISTRY_USERNAME }}
        password: ${{ secrets.REGISTRY_PASSWORD }}
```

**Q9：如何查看 workflow 运行日志？**

- 进入仓库 → `Actions` 标签页
- 点击具体的 workflow 运行记录
- 点击各个 job 和 step 查看详细日志

**Q10：项目需要同时使用多个类型的 NPU 怎么办？**

- 在申请时同时申请多个 Runner（多个名称用逗号分隔）
- 例如：`runner-names: linux-arm64-npu-1, linux-aarch64-310p-2`
- 在不同 job 中使用不同的 `runs-on` 标签

---

## 反馈与支持

如果在接入过程中遇到任何问题，请通过以下方式反馈：

- **提交 Discussion**：[https://github.com/ascend-gha-runners/docs/discussions](https://github.com/ascend-gha-runners/docs/discussions)
- 提交时，请提供以下信息：
  - 项目名称和 Git 仓库地址
  - 问题描述和错误日志截图
  - 已完成的步骤和卡住的环节
  - 使用的安装方式（GitHub App 或 PAT）
  - Runner 名称和状态

---

*文档版本: v2.0*  
*最后更新: 2026-04-28*