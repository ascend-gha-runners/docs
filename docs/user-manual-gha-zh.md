# GitHub Actions 接入昇腾算力指导

我们基于[ARC](https://github.com/actions/actions-runner-controller/)实现 GitHub Action 任务在昇腾集群节点上执行。

## Runner pod 类型及命名方式

昇腾集群创建 runner pod 执行 Github Action job。
我们提供如下类型的昇腾芯片。如果您未指定名称，我们将使用默认命名。

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
│ 步骤 2: 准备权限                                       │
│ 你：获取组织或仓库管理权限                            │
│ 验收：具备必要权限                                    │
└────────────────────────┬──────────────────────────────┘
                         │
                         ├─────────┬─────────┬─────────┐
                         │         │         │         │
                         ▼         ▼         ▼         ▼
                    ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
                    │组织+App│ │仓库+App│ │组织+PAT│ │仓库+PAT│
                    └────────┘ └────────┘ └────────┘ └────────┘
                         │         │         │         │
                         └─────────┴─────────┴─────────┴─────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 3: 安装 GitHub App 或创建 PAT                    │
│ 你：按照选择的方案执行安装或创建                      │
│ 验收：App 已安装或 PAT 已生成                        │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 4: 提交激活申请                                   │
│ 你：通过 Issue 或邮件提交申请                         │
│ 我们：部署和配置 Runner                               │
│ 验收：收到申请确认                                    │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 5: 验证 Runner 可用                              │
│ 你：在仓库 Settings 查看 Runner 状态                   │
│ 验收：Runner 状态显示 Online                          │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
┌───────────────────────────────────────────────────────┐
│ 步骤 6: 在 Workflow 中使用 Runner                     │
│ 你：编写 workflow 并指定 Runner 标签                  │
│ 验收：Workflow 成功运行                               │
└────────────────────────┬──────────────────────────────┘
                         │
                         ▼
                     完成接入
```

## 安装

我们按照安装范围(组织/仓库)和接入权限(GitHub App/PAT)分别介绍安装方式。您可以选择其中一种种方式安装，也可以搭配多种方式混合安装。
如果安装到组织，可以在仓库间复用 runner。并且可以通过 runner group 限制仓库范围。如果安装到仓库，只有单个仓库可以使用 runner。
GitHub App 权限更安全，但是需要组织管理者权限。如果觉得很难获取组织层面的许可，可以选择 PAT 权限。
如果您在安装/使用过程中有任何问题，请[提出discussion](https://github.com/ascend-gha-runners/docs/discussions)。

||组织|仓库|
|--|--|--|
|GitHub App|[安装方式](#通过-github-app-将-runner-安装到组织)|[安装方式](#通过-github-app-将-runner-安装到仓库)|
|PAT|[安装方式](#通过-pat-将-runner-安装到组织)|[安装方式](#通过-pat-将-runner-安装到仓库)|

---

## 通过 GitHub App 将 runner 安装到组织

### 准备工作

需要具备组织的管理权限。

### 可选：安装 runner group

被安装到组织的 runner 由 runner group 管理。
runner group 有3个配置选项以控制仓库的 workflow 是否可以使用 runner。
1. 仓库：选择组织下所有仓库 / 选择指定仓库。
2. 仓库访问权限：private / public。
3. workflow: 选择所有 workflow / 选择指定 workflow。
同时满足3个配置的仓库可以使用组织的 runner。

如果没有指定 runner group，则使用默认 runner group，其默认配置是：
1. 仓库：选择所有仓库。
2. 仓库访问权限： private。
3. workflow: 选择所有 workflow。

您可以使用并更改默认 runner group 来管理 runner，跳过[新建 runner group](#新建-runner-group)。
如果默认 runner group 已经管理 runner 并且其权限与新 runner 不同，您可以参考[新建 runner group](https://docs.github.com/en/actions/how-tos/hosting-your-own-runners/managing-self-hosted-runners/managing-access-to-self-hosted-runners-using-groups#creating-a-self-hosted-runner-group-for-an-organization)创建自定义 runner group 来管理 runner。

### 安装 GitHub App

**你需要做什么**：

浏览器访问[apps/ascend-runner-mgmt][1]并且点击`Install`。
![alt text](assets/user-manual-zh/image-3.png)
选择组织，选择`All repositories`，点击`Install`。
![alt text](assets/user-manual-zh/image-19.png)

**怎么验证这步完成**：

- GitHub App 已安装到目标组织

### 提交申请激活组织

**你需要做什么**：

浏览器访问[ascend-gha-runners/org-archive/issues][2]并且依次点击`New issue`, `Add Or Modify Organization`选择模板。
![alt text](assets/user-manual-zh/image-17.png)
填写3个配置参数后点击`Create`。如果您需要自定义 runner 名称，请在 issue 中说明。
- `org-name`表示您的组织名称。
- `runner-group-name`表示`Runner group`的名称，默认`Default`。
- `runner-names`表示 Runner 的名称。
![alt text](assets/user-manual-zh/image-1.png)

**我们做什么**：

- 收到申请后部署和配置 Runner

**怎么验证这步完成**：

- Issue 已提交并收到确认回复

---

## 通过 GitHub App 将 runner 安装到仓库

### 准备工作

需要具备组织及仓库的管理权限。

### 安装 GitHub App

**你需要做什么**：

浏览器访问[apps/ascend-runner-mgmt][1]并且点击`Install`。
![alt text](assets/user-manual-zh/image-3.png)
选择组织，选择`Only select repositories`，选择目标仓库，点击`Install`。
![alt text](assets/user-manual-zh/image-18.png)

**怎么验证这步完成**：

- GitHub App 已安装到目标仓库

### 提交申请激活仓库

**你需要做什么**：

浏览器访问[ascend-gha-runners/org-archive/issues][2]并且依次点击`New issue`, `Add Or Modify Repository`选择模板。
![alt text](assets/user-manual-zh/image-20.png)
填写2个配置参数后点击`Create`。如果您需要自定义 runner 名称，请在 issue 中说明。
- `repo-name`表示您的仓库名称。
- `runner-names`表示 Runner 的名称。
![alt text](assets/user-manual-zh/image-2.png)

**我们做什么**：

- 收到申请后部署和配置 Runner

**怎么验证这步完成**：

- Issue 已提交并收到确认回复

---

## 通过 PAT 将 runner 安装到组织

### 准备工作

需要具备组织的管理权限。

### [可选:安装-runner-group](#可选安装-runner-group)

### 创建 token

**你需要做什么**：

根据[GitHub Docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic)创建token。
scopes 选择`admin:org`。
请注意token到期时间，token到期之后仓库不显示 Runner scale set，无法执行 workflow，需要重新生成有效token。
![alt text](assets/user-manual-zh/image-23.png)

**怎么验证这步完成**：

- PAT 已创建并妥善保存

### 提交申请激活组织

**你需要做什么**：

考虑到token保密需求，申请方式是向`gouzhonglin@huawei.com`发送邮件。如果您需要自定义 runner 名称，请在邮件中说明。
邮件主题模板：`Request Ascend NPU Runners`
邮件内容模板：
```yaml
repo: https://github.com/my-org/
runner-group: ascend-ci
token: ghp_xxx
expire-at: 30days
runner-names: linux-arm64-npu-1
```

**我们做什么**：

- 收到申请后部署和配置 Runner

**怎么验证这步完成**：

- 邮件已发送并收到确认回复

---

## 通过 PAT 将 runner 安装到仓库

### 准备工作

需要具备仓库的管理权限。

### 创建 token

**你需要做什么**：

根据[GitHub Docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic)创建token。
scopes 选择`repo`。
请注意token到期时间，token到期之后仓库不显示 Runner scale set，无法执行 workflow，需要重新生成有效token。

![alt text](assets/user-manual-zh/image-16.png)

**怎么验证这步完成**：

- PAT 已创建并妥善保存

### 提交申请激活仓库

**你需要做什么**：

考虑到token保密需求，申请方式是向`gouzhonglin@huawei.com`发送邮件。如果您需要自定义 runner 名称，请在邮件中说明。
邮件主题模板：`Request Ascend NPU Runners`
邮件内容模板：
```yaml
repo: https://github.com/my-org/my-repo
token: ghp_xxx
expire-at: 30days
runner-names: linux-arm64-npu-1
```

**我们做什么**：

- 收到申请后部署和配置 Runner

**怎么验证这步完成**：

- 邮件已发送并收到确认回复

---

## 使用

### 查看 Runner

**你需要做什么**：

无论是将 runner 安装到仓库还是组织，启动 runner 的都是仓库里的workflow。进入您的仓库，依次点击组织的`Settings, Actions, Runner `。
- `Runner scale set`目录下是配置到仓库的 runner。
- `Shared with this repository`目录下是仓库可以访问的组织 runner。
- `Status`为`Online`表示可以使用。
![alt text](assets/user-manual-zh/image-24.png)

**怎么验证 Runner 可用**：

- Runner 状态显示为 **Online**（绿色圆点）

### 在workflow中使用NPU Runners

**你需要做什么**：

如果想在 job 中使用昇腾芯片，需要指定`container.image`字段，否则job不会调用NPU资源。
以下例子展示Github Action workflow如何使用NPU Runners。

```yaml
name: Test NPU Runner
on:
  workflow_dispatch:
jobs:
  job_0:
    runs-on: linux-arm64-npu-1
    container:
      image: ascendai/cann:latest
      
    steps:
      - name: Show NPU info
        run: |
          npu-smi info
```

**怎么验证 Workflow 正常运行**：

- Workflow 成功触发并运行
- 日志中能看到 NPU 信息

---

## 常见问题

**Q1：如何知道我的组织是否有权限安装 GitHub App？**

需要组织的 Owner 权限。如果不确定，请联系你的组织管理员。

**Q2：Runner 状态一直是 Offline 怎么办？**

- 检查 GitHub App 是否正确安装
- 检查 PAT 是否有效且未过期
- 确认 Runner Group 权限配置是否正确
- 联系基础设施团队排查

**Q3：workflow 一直在等待 Runner，无法运行？**

- 确认 `runs-on` 字段的值与申请的 Runner 名称完全一致
- 检查 Runner 状态是否为 Online
- 确认仓库有权访问该 Runner（Runner Group 配置）

**Q4：PAT 过期了怎么办？**

- 重新生成 PAT
- 通过邮件将新 Token 发送给基础设施团队
- 等待基础设施团队更新配置

**Q5：如何在多个仓库间共享 Runner？**

- 使用组织级安装（通过 GitHub App 或 PAT 安装到组织）
- 通过 Runner Group 控制哪些仓库可以访问 Runner

---

## 反馈与支持

如果您在安装/使用过程中有任何问题，请[提出discussion](https://github.com/ascend-gha-runners/docs/discussions)。

提交时，请提供以下信息：
- 项目名称和 Git 仓库地址
- 问题描述和错误信息
- 使用的安装方式（GitHub App 或 PAT）

---

[1]: https://github.com/apps/ascend-runner-mgmt
[2]: https://github.com/ascend-gha-runners/org-archive/issues