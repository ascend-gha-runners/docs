---
name: case-induction
description: 每周案例归纳回灌流程。从 problem-tracking / self-resolved 已关闭 issue 归纳候选案例，生成 review 检查单与最新决策路径表，人工检查后回灌 problem-tree.json / error-types.md。当用户说「跑案例归纳」「每周归纳」「归纳回灌」时使用。
---

# 每周案例归纳（自助解决问题 · P2 回灌流程）

目的：把本周已关闭的问题登记 issue 归纳为可复用案例，经**人工检查**后回灌文档，形成闭环。
原则：AI 只产出候选，**人工勾选确认后才改动线上文档**；禁止全自动回灌（防幻觉）。

## 固定步骤

### 1. 拉取数据源

```bash
python scripts/case-induction/fetch_issues.py
```

- 默认区间：上次 dump 截止日的次日 → 今天（首次默认最近 7 天）
- 产出：`<仓库上级>/case-induction-data/dump-<起>-<止>.md`（issue 正文 + 全部评论）
- **dump 不入库**：它是 issue 原文聚合，可能含内网 IP / 内部域名 / 内部镜像仓库路径 / 私有仓库链接，且进 git 历史后不可逆。只放仓库外本地，**禁止提交到仓库**（CI 的 `sensitive-check` 会拦仓库内被跟踪的 `case-induction/dump-*.md`）。

### 2. AI 归纳，生成 review

阅读三份材料：
- `<仓库上级>/case-induction-data/dump-<起>-<止>.md`（本期数据）
- `docs/assets/problem-tree.json`（当前决策树）
- 案例库：中文 `docs/error-types-zh.md`、英文 `docs/error-types.md`（双语，决策树锚点指向中文页）

产出 `<仓库上级>/case-induction-data/review-<起>-<止>.md`，**必须严格使用本文末的模板**，字段不得增删。
**review 同样不入库**（是对原文的复述，会带上同样的内网标识）。

### 3. 按勾选项改决策树，生成最新路径表

只按 review 中**人工已勾选**的项修改 `docs/assets/problem-tree.json` / 案例库（中文 `docs/error-types-zh.md`、英文 `docs/error-types.md`），然后：

```bash
python scripts/case-induction/export_tree_view.py
```

产出 `case-induction/tree-view.md`：与 git HEAD 已提交版本对比，新增/变化的路径自动标 🆕 并生成可勾选复查清单。

### 4. 人工检查

- review：逐项勾选（`- [x]` 采纳；不采纳的删除或备注原因）
- tree-view：只复查带 🆕 的新增行（已有路径不用重复检查）

### 5. 提交 PR

一个 PR 一起合入：`problem-tree.json` + 案例库 + `tree-view.md`。
**不含 dump / review**（见硬性规则 7）。敏感信息由 CI 的 `sensitive-check` 门禁把关
（`.github/workflows/ci.yml`，扫 `docs/` `case-induction/` `.claude/skills/`），提交前可本地跑同一套正则自查。

**PR 由人工创建、人工安排合入；AI 禁止代建 PR、禁止合并。**

## 硬性规则

1. 只基于 dump 原文归纳，**禁止编造根因 / 结论**；原文无依据的写「待人工确认」
2. 每条候选必须附来源 issue 编号（#xxx）
3. review 必须严格使用下方模板结构，字段不得增删
4. 决策树叶子锚点必须指向案例库中真实存在的标题——案例库已**双语化**：中文页 `docs/error-types-zh.md`（决策树默认指向，标题需带 `{ #anchor }` 显式锚点）、英文页 `docs/error-types.md`（叶子无对应案例时 links 留空，并在 review 中说明）
5. 新增叶子必须带 badge 归属（check-workflow / check-resource / check-github / ci-infra）
6. issue 表单字段可能有误（如 runs-on 填成 runner 实例名 / Other）：归纳以正文与评论的事实为准推测真实标签；无法推测的在「高频问题观察」备注「标签存疑」，不要原样采信
7. **脱敏（强制）**：归纳产物（review / 决策树 / 案例库）一律**不得原样搬入内部标识**，必须按下表替换为占位符；CI 的 `sensitive-check` 门禁会拦（正则见 `.github/workflows/ci.yml`）

| 类型 | 禁止原样搬入 | 替换为 |
| :--- | :--- | :--- |
| 内网 IP | `10.*` / `172.16-31.*` / `192.168.*` 段的地址 | `<internal-ip>` |
| 内部域名 / 挂载路径 | `*.<内部域后缀>:/<共享名>` | `<internal-host>` / `<nfs-export>` |
| 内部镜像仓库 | SWR 主机 + 内部组织段（`base_image/` 下的内部组织名） | `swr.<region>.myhuaweicloud.com/<internal-registry>/...` |
| 租户/集群映射 | `liqo.io/managed-by-namespace-map` 的实值 | 只保留 key，值写 `<tenant-namespace>/<cluster>` |
| 私有仓库链接 | 部署仓（`opensourceways/ascend-ci-deployment`）的 PR / issue 直链 | 「见部署仓对应 PR」，不留 URL / 编号 |
| 凭据 | 任何 token / key / 私钥 / 密码 | 一律不写；需要时只写「见凭据存放位置」 |

> 集群名（gy004 / cn12-001）、runs-on 标签、org/repo 名属**已公开**信息（见 `docs/Cluster.md`），无需脱敏；`.svc.cluster.local` 服务名在部署/使用手册中属有意公开，案例库也不强制脱敏。

## review 模板（生成 review-<起>-<止>.md 时逐字套用）

```markdown
# 案例归纳 review（<起> ~ <止>）

> 生成：<日期>；数据源：dump-<起>-<止>.md（N 个 issue）
> 用法：逐项人工勾选（- [x] 采纳 / 删除不采纳项）；勾选后按建议改对应文件，再跑 export_tree_view.py。

## 一、本期概览
- issue 总数：N（problem-tracking x，self-resolved y）
- 转人工高频：<runs-on 标签 / 仓库 + 次数>
- 自查路径命中：<有「### 自查路径」的 issue 数；最常见命中叶子。注：命中「其它 → 其它问题」不计入有效命中（用户没找到匹配案例才转人工）>

## 二、决策树变更建议
- [ ] 【新增叶子】<标题>
  - 位置：<父节点路径，如 报错 / Job 失败 → Running（运行中报错）>
  - 现象：<一句话>
  - 根因：<一句话；dump 原文无依据写「待人工确认」>
  - 解决步骤：<1. … 2. … 3. …>
  - 建议锚点：<error-types.md 已有标题的 #anchor；无对应案例写「需同步新增 error-types 案例」>
  - badge：<check-workflow / check-resource / check-github / ci-infra>
  - 来源：#<issue 号>
- [ ] 【修改叶子】<节点 id> · <summary/steps/links/badge/title>：<改什么 → 改成什么>（来源：#xxx；一行一个改动点，多处改动分行写）

（无建议时写「本期无」）

## 三、error-types.md 案例增补建议
- [ ] 【新增案例】<标题>
  - 现象：<一句话>
  - 根因：<一句话；无依据写「待人工确认」>
  - 解决：<步骤>
  - 来源：#<issue 号>

（无建议时写「本期无」）

## 四、锚点失效报告
| 叶子 | 当前锚点 | 失效原因 | 建议 |
| :--- | :--- | :--- | :--- |

（无失效写「本期无」）

## 五、高频问题观察（仅供人工参考，无需勾选）
| runs-on 标签 | 仓库 | 次数 | 代表 issue |
| :--- | :--- | :--- | :--- |
```
