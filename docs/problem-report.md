---
title: 问题登记
---

<div class="problem-report">

<style>
/* 独立页：隐藏站点左右侧栏，让内容区占满可用全宽 */
.md-sidebar--primary, .md-sidebar--secondary { display: none !important; }
.md-main__inner { max-width: none !important; grid-template-columns: 1fr !important; }
.md-content { grid-column: 1 !important; }
.md-content__inner { max-width: none !important; }

.problem-report { max-width: none; }
.problem-report h2 { font-size: 1.05rem; margin: 0 0 0.5rem; }
.problem-report h3 { font-size: 0.9rem; margin: 0 0 0.5rem; }

/* 左右布局：左侧步骤流程，右侧表单 */
.pr-layout { display: flex; gap: 1.6rem; align-items: flex-start; }
.pr-sidenav { flex: 0 0 12.5rem; position: sticky; top: 5rem; }

/* 左侧：节点 + 连线 */
.pr-steps-v { list-style: none; margin: 0; padding: 0; }
.pr-step { position: relative; display: flex; gap: 0.7rem; padding: 0 0 1.4rem 0; }
.pr-step:not(:last-child)::after {
  content: ''; position: absolute; left: 0.9rem; top: 1.75rem; bottom: 0;
  width: 2px; background: var(--md-default-fg-color--lightest);
}
.pr-step-dot {
  position: relative; z-index: 1; flex-shrink: 0; width: 1.8rem; height: 1.8rem;
  border-radius: 50%; display: inline-flex; align-items: center; justify-content: center;
  font-size: 0.82rem; font-weight: 700; background: var(--md-default-bg-color);
  border: 2px solid var(--md-default-fg-color--lightest); color: var(--md-default-fg-color--light);
}
.pr-step-meta { display: flex; flex-direction: column; gap: 0.1rem; padding-top: 0.15rem; }
.pr-step-title { font-size: 0.88rem; color: var(--md-default-fg-color--light); line-height: 1.2; }
.pr-step-sub { font-size: 0.72rem; color: var(--md-default-fg-color--lighter); }
.pr-step.is-done { cursor: pointer; }
.pr-step.is-done .pr-step-dot { background: var(--md-primary-fg-color); border-color: var(--md-primary-fg-color); color: var(--md-default-bg-color); }
.pr-step.is-done:not(:last-child)::after { background: var(--md-primary-fg-color); }
.pr-step.is-done .pr-step-title { color: var(--md-primary-fg-color); }
.pr-step.is-active .pr-step-dot { background: var(--md-primary-fg-color); border-color: var(--md-primary-fg-color); color: var(--md-default-bg-color); box-shadow: 0 0 0 3px var(--md-primary-fg-color--transparent, rgba(0,0,0,0.15)); }
.pr-step.is-active .pr-step-title { color: var(--md-typeset-color); font-weight: 600; }

/* 右侧面板 */
.pr-main { flex: 1 1 auto; min-width: 0; }
.pr-panel { border: 1px solid var(--md-default-fg-color--lightest); border-radius: 12px; background: var(--md-default-bg-color--light); padding: 0.75rem 0.95rem 0.85rem; margin-bottom: 0.8rem; }

/* 搜索（复用 Cluster 风格） */
.pr-repo-search { width: 100%; max-width: none; margin-bottom: 0.75rem; }

/* 项目/标签选择胶囊 */
.pr-pills { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.pr-pill {
  padding: 0.35rem 0.85rem; font-size: 0.8rem; color: var(--md-typeset-color);
  background: var(--md-default-bg-color); border: 1px solid var(--md-default-fg-color--lightest);
  border-radius: 999px; cursor: pointer; transition: border-color 0.2s, box-shadow 0.2s, color 0.2s;
}
.pr-pill:hover { border-color: var(--md-primary-fg-color); color: var(--md-primary-fg-color); }
.pr-pill.is-selected { border-color: var(--md-primary-fg-color); background: rgba(66, 140, 255, 0.18); color: var(--md-typeset-color); box-shadow: 0 0 0 3px var(--md-primary-fg-color--transparent, rgba(66, 140, 255, 0.15)); }
.pr-pills .pr-pill.is-match { border-color: var(--md-primary-fg-color); box-shadow: 0 0 0 1.5px var(--md-primary-fg-color); }
.pr-pill-sm { font-family: var(--md-code-font-family); font-size: 0.72rem; padding: 0.22rem 0.6rem; }
.pr-pill-other { color: var(--md-default-fg-color--light); }

/* 表单字段 */
.pr-field { margin: 0.6rem 0; }
.pr-field label { display: block; font-weight: 600; font-size: 0.85rem; margin-bottom: 0.3rem; }
.problem-report input[type="text"], .problem-report input[type="search"], .problem-report input[type="number"], .problem-report textarea {
  width: 100%; padding: 0.5rem 0.7rem; font-size: 0.85rem; box-sizing: border-box;
  color: var(--md-typeset-color); background: var(--md-default-bg-color);
  border: 1px solid var(--md-default-fg-color--lightest); border-radius: 8px; outline: none;
  transition: border-color 0.2s, box-shadow 0.2s;
}
.problem-report input:focus, .problem-report textarea:focus {
  border-color: var(--md-primary-fg-color); box-shadow: 0 0 0 3px var(--md-primary-fg-color--transparent, rgba(0,0,0,0.15));
}
.problem-report textarea { font-family: inherit; resize: vertical; }
.pr-hint { font-size: 0.78rem; color: var(--md-default-fg-color--light); margin: 0.25rem 0 0; }

/* 紧急程度 */
.pr-urgency-row { display: flex; align-items: center; gap: 0.6rem; }
.pr-select {
  width: 100%; padding: 0.5rem 0.6rem; font-size: 0.85rem; box-sizing: border-box;
  color: var(--md-typeset-color); background: var(--md-default-bg-color);
  border: 1px solid var(--md-default-fg-color--lightest); border-radius: 8px; outline: none;
  transition: border-color 0.2s, box-shadow 0.2s;
}
.pr-urgency-row .pr-select { flex: 0 0 50%; }  /* 下拉框占一半，右侧留给 xx内解决 */
.pr-select:focus { border-color: var(--md-primary-fg-color); box-shadow: 0 0 0 3px var(--md-primary-fg-color--transparent, rgba(0,0,0,0.15)); }
.pr-urgency-num { display: flex; align-items: center; gap: 0.45rem; }
.pr-urgency-num[hidden] { display: none; }  /* 确保 hidden 属性生效（覆盖上面的 display） */
.pr-urgency-num input[type="number"] { flex: 0 0 5rem; }
.pr-urgency-unit { font-size: 0.78rem; color: var(--md-default-fg-color--light); white-space: nowrap; }

/* 现象描述四段式 */
.pr-desc-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0 1rem; }
.pr-desc-grid .pr-field { margin: 0.35rem 0; }
.pr-desc-grid .pr-desc-no { display: inline-block; min-width: 1.35rem; height: 1.35rem; border-radius: 50%; background: var(--md-default-fg-color--lightest); color: var(--md-default-bg-color); font-size: 0.72rem; font-weight: 700; text-align: center; line-height: 1.35rem; margin-right: 0.35rem; }

/* 任务类型 / 执行过程：自定义下拉（宽度与输入框一致，主题蓝样式） */
.pr-cb { position: relative; }
.pr-cb-list {
  position: absolute; top: calc(100% + 4px); left: 0; right: 0; z-index: 50;
  list-style: none; margin: 0; padding: 0.3rem; max-height: 220px; overflow: auto;
  background: var(--md-default-bg-color); border: 1px solid var(--md-default-fg-color--lightest);
  border-radius: 8px; box-shadow: var(--md-shadow-z2, 0 2px 8px rgba(0, 0, 0, 0.2));
}
.pr-cb-list li { padding: 0.4rem 0.6rem; font-size: 0.82rem; border-radius: 6px; cursor: pointer; color: var(--md-typeset-color); }
.pr-cb-list li:hover, .pr-cb-list li.is-active { background: rgba(66, 140, 255, 0.15); }
.pr-cb-list li[hidden] { display: none; }
.pr-cb-list .pr-cb-empty { cursor: default; color: var(--md-default-fg-color--light); }

/* 自查清单 */
.pr-selfcheck { margin-top: 0.9rem; padding: 0.6rem 0.9rem; border: 1px dashed var(--md-default-fg-color--lightest); border-radius: 10px; font-size: 0.82rem; }
.pr-selfcheck label { display: block; margin: 0.25rem 0; cursor: pointer; }
.pr-selfcheck .pr-field { margin: 0.55rem 0 0.3rem; }

/* 摘要 */
.pr-summary { margin-bottom: 1rem; }
.pr-summary-table { width: 100%; font-size: 0.82rem; }
.pr-summary-table th { width: 8rem; text-align: left; vertical-align: top; color: var(--md-default-fg-color--light); font-weight: 500; padding: 0.25rem 0.5rem 0.25rem 0; }
.pr-summary-table td { padding: 0.25rem 0; word-break: break-all; }

/* 按钮 */
.pr-btn {
  display: inline-block; background: var(--md-primary-fg-color); color: var(--md-default-bg-color);
  border: none; border-radius: 999px; padding: 0.55rem 1.3rem; font-size: 0.88rem; cursor: pointer;
  text-decoration: none; transition: opacity 0.2s;
}
.pr-btn:hover { opacity: 0.88; }
.pr-btn:disabled { opacity: 0.5; cursor: not-allowed; }
.pr-btn[hidden] { display: none; }  /* 确保 hidden 属性生效（覆盖上面的 display） */
.pr-btn-ghost { background: none; border: 1px solid var(--md-default-fg-color--lightest); color: var(--md-typeset-color); }
.pr-btn-sm { padding: 0.42rem 0.95rem; font-size: 0.8rem; }
.pr-nav { display: flex; justify-content: flex-end; gap: 0.75rem; margin-top: 0.5rem; }
.pr-error { color: #d93025; font-size: 0.82rem; margin: 0.6rem 0 0; }
.pr-result { margin-top: 0.9rem; font-size: 0.85rem; }
.pr-link { font-size: 0.85rem; word-break: break-all; }

@media (max-width: 76.25rem) {
  .pr-layout { flex-direction: column; }
  .pr-sidenav { flex: none; width: 100%; position: static; }
  .pr-steps-v { display: flex; gap: 0.75rem; }
  .pr-step { flex: 1; flex-direction: column; align-items: center; text-align: center; padding: 0; }
  .pr-step:not(:last-child)::after { left: 50%; top: 1.8rem; right: -50%; width: 100%; height: 2px; bottom: auto; }
  .pr-desc-grid { grid-template-columns: 1fr; }
}
</style>

<div class="pr-layout">

  <aside class="pr-sidenav">
    <ol class="pr-steps-v" aria-label="登记流程">
      <li class="pr-step is-active" data-step="1">
        <span class="pr-step-dot">1</span>
        <span class="pr-step-meta"><span class="pr-step-title">自查与自助</span><span class="pr-step-sub">先自查能否解决</span></span>
      </li>
      <li class="pr-step" data-step="2">
        <span class="pr-step-dot">2</span>
        <span class="pr-step-meta"><span class="pr-step-title">选择项目</span><span class="pr-step-sub">仓库 / 社区</span></span>
      </li>
      <li class="pr-step" data-step="3">
        <span class="pr-step-dot">3</span>
        <span class="pr-step-meta"><span class="pr-step-title">确认标签</span><span class="pr-step-sub">runs-on</span></span>
      </li>
      <li class="pr-step" data-step="4">
        <span class="pr-step-dot">4</span>
        <span class="pr-step-meta"><span class="pr-step-title">描述问题</span><span class="pr-step-sub">URL / 现象</span></span>
      </li>
      <li class="pr-step" data-step="5">
        <span class="pr-step-dot">5</span>
        <span class="pr-step-meta"><span class="pr-step-title">提单与生成</span><span class="pr-step-sub">提单人 / Issue</span></span>
      </li>
    </ol>
  </aside>

  <div class="pr-main">
    <form id="pr-form" autocomplete="off">

      <section class="pr-panel" data-step="1">
        <h2>1 · 自查与自助</h2>
        <p class="pr-hint">先按以下清单自查，很多问题可以自助解决、无需登记；确认仍需要登记再点「下一步」继续。</p>
        <div class="pr-selfcheck">
          <h3>自查清单</h3>
          <label><input type="checkbox" id="pr-running"> 是否正在运行？（正在运行可查看后台日志，信息更丰富）</label>
          <label><input type="checkbox" id="pr-known"> 是否为已知问题？（可查看 <a href="/docs/error-types/" target="_blank" rel="noopener">Job Failure Reference</a>，新标签页打开）</label>
        </div>
      </section>

      <section class="pr-panel" data-step="2" hidden>
        <h2>2 · 选择项目</h2>
        <p class="pr-hint">输入关键字搜索，或从列表中选择出现问题的仓库。</p>
        <input type="search" id="pr-repo-input" class="cluster-filter pr-repo-search"
               placeholder="搜索项目，例如 vllm-ascend…" autocomplete="off" aria-label="搜索项目">
        <div id="pr-repo-options" class="pr-pills pr-options"></div>
      </section>

      <section class="pr-panel" data-step="3" hidden>
        <h2>3 · 确认 runs-on 标签</h2>
        <p class="pr-hint" id="pr-label-hint"></p>
        <input type="search" id="pr-label-search" class="pr-repo-search"
               placeholder="搜索标签，例如 a2b3…" autocomplete="off" aria-label="搜索 runs-on 标签">
        <div id="pr-label-options" class="pr-pills pr-options"></div>
      </section>

      <section class="pr-panel" data-step="4" hidden>
        <h2>4 · 描述问题</h2>
        <div class="pr-field">
          <label for="pr-url">问题 URL * <span class="pr-hint">（出问题的 PR 或 Job，GitHub Action 页面可见）</span></label>
          <textarea id="pr-url" rows="2" placeholder="粘贴出问题的 PR 或 GitHub Action Job 链接，可粘贴多个，用换行/空格/中英文逗号分隔"></textarea>
        </div>
        <div class="pr-field">
          <label>简单描述你看到的现象 *</label>
          <div class="pr-desc-grid">
            <div class="pr-field">
              <label for="pr-desc-task"><span class="pr-desc-no">1</span>任务类型</label>
              <div class="pr-cb">
                <input type="text" id="pr-desc-task" placeholder="选择或输入，例如：vllm-ascend 编译" autocomplete="off">
                <ul class="pr-cb-list" id="pr-cb-task-list" hidden></ul>
              </div>
            </div>
            <div class="pr-field">
              <label for="pr-desc-proc"><span class="pr-desc-no">2</span>执行过程</label>
              <div class="pr-cb">
                <input type="text" id="pr-desc-proc" placeholder="选择或输入，例如：Running运行" autocomplete="off">
                <ul class="pr-cb-list" id="pr-cb-proc-list" hidden></ul>
              </div>
            </div>
            <div class="pr-field">
              <label for="pr-desc-problem"><span class="pr-desc-no">3</span>出现的问题 *</label>
              <textarea id="pr-desc-problem" rows="2" placeholder="例如：不同架构编译产物冲突导致失败"></textarea>
            </div>
            <div class="pr-field">
              <label for="pr-err">错误信息</label>
              <textarea id="pr-err" rows="2" placeholder="粘贴关键报错，如 undefined symbol / connection refused…"></textarea>
            </div>
            <div class="pr-field">
              <label for="pr-desc-expected"><span class="pr-desc-no">4</span>预期</label>
              <input type="text" id="pr-desc-expected" placeholder="例如：应能正常编译通过">
            </div>
            <div class="pr-field">
              <label for="pr-urgency">紧急程度</label>
              <div class="pr-urgency-row">
                <select id="pr-urgency" class="pr-select">
                  <option value="提示">提示</option>
                  <option value="一般" selected>一般</option>
                  <option value="重要">重要</option>
                  <option value="紧急">紧急</option>
                </select>
                <div class="pr-urgency-num" id="pr-urgency-num" hidden>
                  <input type="number" id="pr-urgency-value" min="1" max="30" step="1" value="3">
                  <span class="pr-urgency-unit" id="pr-urgency-unit">天内解决</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="pr-panel" data-step="5" hidden>
        <h2>5 · 提单与生成提交</h2>
        <div class="pr-field">
          <label for="pr-reporter">提单人 *</label>
          <input type="text" id="pr-reporter" placeholder="姓名 工号，例如：张三 12345">
        </div>
        <p class="pr-hint">确认信息无误后，点击按钮打开预填好的 GitHub Issue 页，提交即完成登记。</p>
        <div id="pr-summary" class="pr-summary"></div>
        <button type="button" id="pr-generate" class="pr-btn">打开预填的 GitHub Issue 页</button>
        <button type="button" id="pr-copy" class="pr-btn pr-btn-ghost">复制链接</button>
        <button type="button" id="pr-reset" class="pr-btn pr-btn-ghost" hidden>重新登记</button>
        <div id="pr-result" class="pr-result"></div>
      </section>

      <p id="pr-error" class="pr-error" hidden></p>

      <div class="pr-nav">
        <button type="button" id="pr-prev" class="pr-btn pr-btn-ghost" hidden>上一步</button>
        <button type="button" id="pr-next" class="pr-btn">下一步</button>
      </div>

    </form>
  </div>

</div>
</div>
