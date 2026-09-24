#!/usr/bin/env python3
"""拉取「问题登记」相关 issues（正文 + 全部评论），生成案例归纳数据源 dump。

用法:
    python fetch_issues.py                                  # 从上次 dump 结尾的次日拉到今天（首次默认最近 7 天）
    python fetch_issues.py --since 2026-09-15 --until 2026-09-22

参数:
    --repo      仓库，默认 ascend-gha-runners/docs
    --labels    逗号分隔的 issue 标签，默认 problem-tracking,self-resolved
    --since     起始日期 YYYY-MM-DD（按关闭时间过滤，含当天）
    --until     截止日期 YYYY-MM-DD（含当天，默认今天）
    --out-dir   输出目录，默认 <仓库根上级>/case-induction-data（仓库外，不入库）
    --token     GitHub Token（也可通过环境变量 GITHUB_TOKEN / GH_TOKEN 提供）

说明:
    - 依赖仅 Python 3.7+ 标准库（urllib / json）。
    - 时间段默认规则：扫描输出目录中最新的 dump-<起>-<止>.md，取其「止」的次日作为本次
      起始日期；目录无 dump 时默认最近 7 天。--since/--until 可显式覆盖。
    - 输出 dump-<起>-<止>.md：每个 issue 一节（编号 / 标题 / 标签 / 时间 / 正文 / 逐条评论）。
    - **dump 不入库**：它是 issue 正文+评论的原文聚合，可能含内网 IP / 内部域名 / 内部镜像
      仓库路径 / 私有仓库链接，且一旦进 git 历史即不可逆。默认输出到仓库外，仅在本地给 AI
      归纳用；仓库根的 case-induction/dump-*.md 已由 .gitignore 兜底忽略。
    - 公仓库可省略 Token（受匿名限流 60 次/小时影响）；评论逐 issue 拉取，issue 较多时建议提供 Token。
"""

import argparse
import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request

DEFAULT_REPO = "ascend-gha-runners/docs"
DEFAULT_LABELS = "problem-tracking,self-resolved"

# 仓库根目录（本脚本位于 scripts/case-induction/ 下）
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# dump 不入库：默认写到仓库外（仓库根的同级目录），仅本地 AI 归纳使用
DEFAULT_OUT_DIR = os.path.join(os.path.dirname(REPO_ROOT), "case-induction-data")

DUMP_NAME_RE = re.compile(r"^dump-(\d{8})-(\d{8})\.md$")


def gh_get(url, token):
    """GET GitHub API，返回解析后的 JSON；失败打印原因并退出。"""
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "case-induction-fetch"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.stderr.write(f"[错误] 请求 GitHub API 失败: HTTP {e.code} {e.reason}\n  URL: {url}\n")
        sys.stderr.write("  可能原因: 仓库不存在 / 标签不存在 / Token 无权限 / 匿名限流\n")
        sys.exit(1)


def fetch_closed_issues(repo, label, token):
    """分页拉取指定标签的全部已关闭 issues。"""
    issues = []
    page = 1
    while True:
        url = (
            f"https://api.github.com/repos/{repo}/issues"
            f"?state=closed&per_page=100&page={page}"
            f"&labels={urllib.parse.quote(label)}"
        )
        batch = gh_get(url, token)
        if not batch:
            break
        issues.extend(i for i in batch if "pull_request" not in i)  # 排除 PR
        if len(batch) < 100:
            break
        page += 1
    return issues


def fetch_comments(repo, number, token):
    """分页拉取一个 issue 的全部评论。"""
    comments = []
    page = 1
    while True:
        url = (
            f"https://api.github.com/repos/{repo}/issues/{number}/comments"
            f"?per_page=100&page={page}"
        )
        batch = gh_get(url, token)
        if not batch:
            break
        comments.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return comments


def parse_date(s):
    """YYYY-MM-DD -> date；失败退出。"""
    try:
        return datetime.date.fromisoformat(s)
    except ValueError:
        sys.stderr.write(f"[错误] 日期格式应为 YYYY-MM-DD: {s}\n")
        sys.exit(1)


def infer_since(out_dir, today):
    """从输出目录最新 dump 文件名推断本次起始日期（上次截止日的次日）；
    无 dump 时默认最近 7 天（含今天）。"""
    last_until = None
    if os.path.isdir(out_dir):
        for name in os.listdir(out_dir):
            m = DUMP_NAME_RE.match(name)
            if m:
                until = datetime.date(
                    int(m.group(2)[:4]), int(m.group(2)[4:6]), int(m.group(2)[6:8]))
                if last_until is None or until > last_until:
                    last_until = until
    if last_until is None:
        return today - datetime.timedelta(days=6)
    return last_until + datetime.timedelta(days=1)


def closed_date(issue):
    """closed_at (ISO) -> date；异常返回 None。"""
    try:
        return datetime.datetime.fromisoformat(
            issue["closed_at"].replace("Z", "+00:00")).date()
    except (ValueError, AttributeError, TypeError):
        return None


def fmt_time(iso):
    """ISO 时间 -> 'YYYY-MM-DD HH:MM UTC'。"""
    try:
        dt = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d %H:%M UTC")
    except (ValueError, AttributeError):
        return iso or "未知"


def fence_for(text):
    """为原文选择安全围栏：默认 4 个波浪号；若原文含等长序列则递增，避免与内容冲突。"""
    n = 4
    while "~" * n in text:
        n += 1
    return "~" * n


def fenced(text):
    """把 issue 正文 / 评论原文用波浪号围栏包起来：原文本身带 markdown（含 ``` 代码块），
    围栏让 dump 结构与原文边界一眼可辨；AI 按边界读取，识别不受影响。"""
    body = (text or "（空）").strip()
    fence = fence_for(body)
    return f"{fence}text\n{body}\n{fence}"


def write_dump(path, issues, comments_map, since, until, repo, labels):
    """写出 dump md：每个 issue 一节（元信息 / 正文 / 逐条评论）。"""
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    lines = [
        f"# 案例归纳数据源 dump（{since.isoformat()} ~ {until.isoformat()}）",
        "",
        f"> 拉取时间：{now}（本地）",
        f"> 仓库：{repo}；标签：{labels}",
        f"> 范围：关闭时间在区间内（含首尾）的 issue，共 {len(issues)} 个",
        "> 用途：仅供本地 AI 每周案例归纳使用，不进入文档站构建。",
        "> 格式：正文 / 评论原文统一包在 ~~~~text 围栏内（原文自带 markdown，围栏仅作边界）。",
        "",
    ]
    for issue in issues:
        num = issue["number"]
        title = issue.get("title", "")
        labs = "、".join(l["name"] for l in issue.get("labels", [])) or "无"
        user = (issue.get("user") or {}).get("login", "未知")
        lines += [
            "---",
            "",
            f"## #{num} {title}",
            "",
            f"- 标签：{labs}",
            f"- 创建：{fmt_time(issue.get('created_at'))} by @{user}",
            f"- 关闭：{fmt_time(issue.get('closed_at'))}",
            "",
            "### 正文",
            "",
            fenced(issue.get("body")),
            "",
        ]
        comments = comments_map.get(num, [])
        lines += [f"### 评论（{len(comments)} 条）", ""]
        if not comments:
            lines += ["（无评论）", ""]
        for c in comments:
            cuser = (c.get("user") or {}).get("login", "未知")
            lines += [
                f"**@{cuser}** · {fmt_time(c.get('created_at'))}",
                "",
                fenced(c.get("body")),
                "",
            ]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"[完成] 已生成 {path}（{len(issues)} 个 issue）")


def main():
    parser = argparse.ArgumentParser(description="拉取案例归纳数据源 dump")
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--labels", default=DEFAULT_LABELS,
                        help="逗号分隔的 issue 标签（默认 problem-tracking,self-resolved）")
    parser.add_argument("--since", help="起始日期 YYYY-MM-DD（含当天）")
    parser.add_argument("--until", help="截止日期 YYYY-MM-DD（含当天，默认今天）")
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"))
    args = parser.parse_args()

    today = datetime.date.today()
    until = parse_date(args.until) if args.until else today
    since = parse_date(args.since) if args.since else infer_since(args.out_dir, today)
    if since > until:
        print(f"[提示] 区间为空（{since} > {until}）：上次 dump 已覆盖到今天，无新增可拉。")
        print("       如需重拉，请用 --since/--until 显式指定区间。")
        return

    print(f"[信息] 拉取区间 {since} ~ {until}（按关闭时间，含首尾）")

    # 多标签分别拉取后按 issue 号合并去重
    seen = {}
    for label in [l.strip() for l in args.labels.split(",") if l.strip()]:
        for issue in fetch_closed_issues(args.repo, label, args.token):
            seen[issue["number"]] = issue

    issues = [i for i in seen.values()
              if closed_date(i) is not None and since <= closed_date(i) <= until]
    issues.sort(key=lambda i: i.get("closed_at") or "")
    print(f"[信息] 区间内共 {len(issues)} 个已关闭 issue，开始拉取评论…")

    comments_map = {}
    for issue in issues:
        num = issue["number"]
        comments_map[num] = fetch_comments(args.repo, num, args.token)

    os.makedirs(args.out_dir, exist_ok=True)
    out_path = os.path.join(
        args.out_dir,
        f"dump-{since.strftime('%Y%m%d')}-{until.strftime('%Y%m%d')}.md")
    write_dump(out_path, issues, comments_map, since, until, args.repo, args.labels)


if __name__ == "__main__":
    main()
