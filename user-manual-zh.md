# 组织管理员->组织/仓库如何为Github Action接入昇腾设备
## 准备工作
需要具备组织的管理权限.

## 1 安装 Github App
浏览器访问[apps/ascend-runner-mgmt][1]并且点击`Install`。
![alt text](assets/user-manual-zh/image-3.png)
选择组织，选择仓库，点击`Install`。
![alt text](assets/user-manual-zh/image-5.png)

## 2 提交申请
### 2.1 配置Runner group
依次点击组织的`Settings`, `Actions`, `Runner groups`, `New runner group`，进入创建页面。
![alt text](assets/user-manual-zh/image-8.png)

在新建页面配置仓库和workflow。保存`Group name`，稍后会用到。
如果想让`public`仓库接入`NPU Runners`，必须点击`Allow public repositories`。
![alt text](assets/user-manual-zh/image-4.png)

### 2.2 提交
浏览器输入`https://github.com/ascend-gha-runners/org-archive/issues`，点击`New issue`选择模板。

- `Add Or Modify Organizaiton`表示新建或者更新组织配置。
- `Delete Organization`表示删除组织。

![alt text](assets/user-manual-zh/image-10.png)
#### 2.3.1 Add Or Modify Organizaiton
填写配置参数后点击`Create`。
`org-name`表示您的组织名称。
`runner-group-name`表示`Runner group`的名称。
`npu-counts`表示NPU Runners挂载的NPU卡数量。
![alt text](assets/user-manual-zh/image-15.png)
#### 2.3.2 Delete Organization
填写配置参数后点击`Create`。
`org-name`表示您的组织名称。
![alt text](assets/user-manual-zh/image-13.png)

# workflow使用者->如何在Github Action中使用昇腾设备
## 1 NPU Runners命名规范
NPU Runners由以下部分组成：
```
linux-amd64-npu-x
^     ^     ^   ^
|     |     |   |
|     |     |   Number of NPUs Available
|     |     NPU Designator
|     Architecture
Operating System
```

## 2 查看 NPU Runners
### 2.1 通过归档文件查看
我们在`https://github.com/ascend-gha-runners/org-archive/tree/main/org-archive/`目录维护接入NPU Runners的所有组织的最新配置状态。在`<your-org>.yaml`中查看您的组织。其中`online-runners`字段展示NPU Runners。

### 2.2 通过Runner group查看
依次点击组织的`Settings, Actions, Runner groups`。在自己配置的runner group里就能看到runners，比如图中的`linux-arm64-npu-1, linux-arm64-npu-2`。
![alt text](assets/user-manual-zh/image-7.png)

## 3 在workflow中使用NPU Runners
NPU jobs必须运行在容器中(比如：`ascendai/cann:latest`)。如果未指定容器，则job不会调用NPU资源。
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

如果有任何问题，请[建立issue](https://github.com/ascend-gha-runners/docs/issues).


[1]: https://github.com/apps/ascend-runner-mgmt