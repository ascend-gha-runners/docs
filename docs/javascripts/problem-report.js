/* 问题登记页（独立页，不进入文档导航）：
   左侧节点流程分步引导：自查与自助 → 选择项目 → 确认 runs-on 标签 → 描述问题 → 提单与生成提交。
   仓库/标签数据来自 assets/problem-labels.json（由导出脚本从 Cluster.md 生成）。
   生成的 Issue 正文以 ### 字段标题 组织，导出脚本按标题解析。 */
(function () {
  'use strict';

  var form = document.getElementById('pr-form');
  if (!form) return;

  function $(id) { return document.getElementById(id); }

  var repoInput = $('pr-repo-input');
  var repoOptions = $('pr-repo-options');
  var labelHint = $('pr-label-hint');
  var labelSearch = $('pr-label-search');
  var labelOptions = $('pr-label-options');
  var urlInput = $('pr-url');
  var descTask = $('pr-desc-task');
  var descProc = $('pr-desc-proc');
  var descProblem = $('pr-desc-problem');
  var descExpected = $('pr-desc-expected');
  var reporterInput = $('pr-reporter');
  var runningChk = $('pr-running');
  var errInput = $('pr-err');
  var knownChk = $('pr-known');
  var urgencySelect = $('pr-urgency');
  var urgencyWrap = $('pr-urgency-num');
  var urgencyInput = $('pr-urgency-value');
  var urgencyUnit = $('pr-urgency-unit');
  var summary = $('pr-summary');
  var genBtn = $('pr-generate');
  var copyBtn = $('pr-copy');
  var resetBtn = $('pr-reset');
  var result = $('pr-result');
  var errorBox = $('pr-error');
  var prevBtn = $('pr-prev');
  var nextBtn = $('pr-next');

  var map = { repos: {} };
  var state = { repo: '', label: '' };
  var currentStep = 1;
  var MAX_STEP = 5;

  // ---------- 决策树（自查与自助） ----------
  var treeContainer = $('pr-tree');
  var treePathEl = $('pr-tree-path');
  var treeNodeEl = $('pr-tree-node');
  var treeSearchEl = $('pr-tree-search');
  var treeResultsEl = $('pr-tree-results');
  var TREE_URL = '../assets/problem-tree.json';
  var treeData = null;
  var treeStart = null;
  var treePath = [];   // [{ from, label, to }]，记录每步选择以支持面包屑回退
  var treeCurrent = null;
  var treeIndex = [];       // 搜索索引：每条 根→叶子 路径的叶子与可检索文本
  var treeSearchTerm = '';  // 本次命中来自搜索时记录关键词，仅用于「已解决」登记打标
  var treeJobRef = '';      // 本次命中来自 Job 链接识别时记录 Job 链接，同样仅用于登记打标
  var jobState = null;      // 最近一次识别成功的 Job（{ url, repo, job }），用于填单与写入 Issue

  // ---------- 埋点（可选，留空则完全不上报） ----------
  // 接收端可以是 1px GIF / 任意返回图片的 URL，用 nginx access log 即可统计；
  // 只上报事件名、叶子 id、搜索词与停留时长，不带仓库、标签、用户信息。
  var TELEMETRY_URL = '';
  var telemetrySid = (function () {
    try {
      var k = 'pr-telemetry-sid';
      var v = sessionStorage.getItem(k);
      if (!v) {
        v = Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
        sessionStorage.setItem(k, v);
      }
      return v;
    } catch (e) {
      return '-';
    }
  })();
  var leafEnteredId = '';
  var leafEnteredAt = 0;
  var searchTrackTimer = null;

  function track(event, data) {
    if (!TELEMETRY_URL) return;
    var qs = new URLSearchParams({ e: event, sid: telemetrySid, ts: Date.now() });
    Object.keys(data || {}).forEach(function (k) {
      var v = data[k];
      if (v === undefined || v === null || v === '') return;
      qs.set(k, String(v).slice(0, 120));
    });
    try {
      var img = new Image();
      img.src = TELEMETRY_URL + (TELEMETRY_URL.indexOf('?') === -1 ? '?' : '&') + qs.toString();
    } catch (e) { /* 埋点失败不影响主流程 */ }
  }

  // 叶子停留时长：离开叶子（切分支 / 跳案例 / 关闭页面）时上报
  function leaveLeaf() {
    if (!leafEnteredId) return;
    track('leaf_leave', { leaf: leafEnteredId, ms: Date.now() - leafEnteredAt });
    leafEnteredId = '';
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('pagehide', leaveLeaf);
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'hidden') leaveLeaf();
    });
  }

  function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function showError(msg) {
    errorBox.textContent = msg || '';
    errorBox.hidden = !msg;
  }

  function setStep(n) {
    currentStep = n;
    showError('');
    document.querySelectorAll('.pr-panel').forEach(function (p) {
      p.hidden = parseInt(p.getAttribute('data-step'), 10) !== n;
    });
    document.querySelectorAll('.pr-steps-v .pr-step').forEach(function (s) {
      var sn = parseInt(s.getAttribute('data-step'), 10);
      s.classList.toggle('is-active', sn === n);
      s.classList.toggle('is-done', sn < n);
    });
    prevBtn.hidden = n === 1;
    nextBtn.hidden = n === MAX_STEP; // 最后一步不再显示“下一步”
    nextBtn.textContent = n === 1 ? '跳过自助，直接提单' : '下一步';
    if (n === MAX_STEP) renderSummary();
  }

  // 左侧节点可点击回到已完成的步骤
  document.querySelectorAll('.pr-steps-v .pr-step').forEach(function (s) {
    s.addEventListener('click', function () {
      var n = parseInt(s.getAttribute('data-step'), 10);
      if (n <= currentStep) setStep(n);
    });
  });

  // ---------- Step 1: 选择项目 ----------
  function renderRepos() {
    var repos = Object.keys(map.repos || {}).sort();
    repoOptions.innerHTML = repos.map(function (r) {
      return '<button type="button" class="pr-pill" data-repo="' + escapeHtml(r) + '">' +
        escapeHtml(r) + '</button>';
    }).join('');
    // 兜底项：输入的内容都不匹配时，Other 会被高亮，点击后用输入的文字作为项目
    repoOptions.insertAdjacentHTML('beforeend',
      '<button type="button" class="pr-pill pr-pill-other" data-repo="__OTHER__" data-other="1">Other</button>');
  }

  // 空格/Tab 分隔多关键词：所有关键词都命中（AND）才算匹配
  function tokenizeSearch(q) {
    return q ? q.toLowerCase().split(/\s+/).filter(Boolean) : [];
  }
  function matchesAllSearch(tokens, text) {
    if (!tokens.length) return true;
    var hay = text.toLowerCase();
    return tokens.every(function (t) { return hay.indexOf(t) !== -1; });
  }

  function filterRepos() {
    var tokens = tokenizeSearch(repoInput.value);
    var shown = 0;
    repoOptions.querySelectorAll('.pr-pill[data-repo]:not([data-other])').forEach(function (b) {
      var ok = tokens.length > 0 && matchesAllSearch(tokens, b.getAttribute('data-repo'));
      b.classList.toggle('is-match', ok);
      if (ok) shown++;
    });
    var other = repoOptions.querySelector('.pr-pill[data-other]');
    if (other) other.classList.toggle('is-match', tokens.length > 0 && shown === 0);
  }
  repoInput.addEventListener('input', filterRepos);
  repoInput.addEventListener('search', filterRepos); // 点击原生 x 清空时同步更新高亮

  function selectRepo(repo) {
    state.repo = repo;
    repoInput.value = repo;
    repoOptions.querySelectorAll('.pr-pill[data-repo]').forEach(function (b) {
      b.classList.toggle('is-selected', b.getAttribute('data-repo') === repo);
    });
    renderLabels();
  }

  function selectOtherRepo() {
    var v = repoInput.value.trim() || 'Other';
    state.repo = v;
    repoInput.value = v;
    repoOptions.querySelectorAll('.pr-pill[data-repo]').forEach(function (b) {
      b.classList.toggle('is-selected', b.getAttribute('data-repo') === '__OTHER__');
    });
    renderLabels();
  }

  repoOptions.addEventListener('click', function (e) {
    var b = e.target.closest('[data-repo]');
    if (!b) return;
    if (b.getAttribute('data-repo') === '__OTHER__') selectOtherRepo();
    else selectRepo(b.getAttribute('data-repo'));
  });

  // ---------- Step 2: 确认 runs-on 标签 ----------
  function renderLabels() {
    var labels = (map.repos && map.repos[state.repo]) || [];
    labelHint.innerHTML = '「' + escapeHtml(state.repo) + '」在 ' +
      '<a href="/docs/Cluster/" target="_blank" rel="noopener">Cluster 文档</a> 中的标签，共 ' +
      labels.length + ' 个，可搜索或点击选择：';
    var html = labels.map(function (l) {
      return '<button type="button" class="pr-pill pr-pill-sm" data-label="' +
        escapeHtml(l) + '">' + escapeHtml(l) + '</button>';
    }).join('');
    // 兜底项：搜索内容都不匹配时，Other 会被高亮，点击后用输入的文字作为标签
    html += '<button type="button" class="pr-pill pr-pill-sm pr-pill-other" data-label="__OTHER__" data-other="1">Other</button>';
    labelOptions.innerHTML = html;
    labelSearch.value = '';
  }

  function filterLabels() {
    var tokens = tokenizeSearch(labelSearch.value);
    var shown = 0;
    labelOptions.querySelectorAll('.pr-pill[data-label]:not([data-other])').forEach(function (b) {
      var ok = tokens.length > 0 && matchesAllSearch(tokens, b.getAttribute('data-label'));
      b.classList.toggle('is-match', ok);
      if (ok) shown++;
    });
    var other = labelOptions.querySelector('.pr-pill[data-other]');
    if (other) other.classList.toggle('is-match', tokens.length > 0 && shown === 0);
  }
  labelSearch.addEventListener('input', filterLabels);
  labelSearch.addEventListener('search', filterLabels); // 点击原生 x 清空时同步更新高亮

  function selectLabel(l) {
    state.label = l;
    labelOptions.querySelectorAll('.pr-pill[data-label]').forEach(function (b) {
      b.classList.toggle('is-selected', b.getAttribute('data-label') === l);
    });
  }

  function selectOtherLabel() {
    var v = labelSearch.value.trim() || 'Other';
    state.label = v;
    labelOptions.querySelectorAll('.pr-pill[data-label]').forEach(function (b) {
      b.classList.toggle('is-selected', b.getAttribute('data-label') === '__OTHER__');
    });
  }

  labelOptions.addEventListener('click', function (e) {
    var b = e.target.closest('[data-label]');
    if (!b) return;
    if (b.getAttribute('data-label') === '__OTHER__') selectOtherLabel();
    else selectLabel(b.getAttribute('data-label'));
  });

  // ---------- 任务类型 / 执行过程：自定义下拉 ----------
  var TASK_OPTIONS = ['PR', 'Test测试', 'function功能', 'Accuracy精度', 'Nightly', 'main2main'];
  var PROC_OPTIONS = ['Waiting等待', 'Running运行', 'Error错误', 'Cancelled取消', 'Queued排队'];

  function initCombobox(inputId, listId, options) {
    var input = $(inputId);
    var list = $(listId);
    if (!input || !list) return;

    function render() {
      var q = input.value.trim().toLowerCase();
      var items = options.filter(function (o) {
        return !q || o.toLowerCase().indexOf(q) !== -1;
      });
      list.innerHTML = items.length
        ? items.map(function (o) {
            return '<li data-val="' + escapeHtml(o) + '">' + escapeHtml(o) + '</li>';
          }).join('')
        : '<li class="pr-cb-empty">无匹配选项</li>';
    }

    function open() { render(); list.hidden = false; }
    function close() { list.hidden = true; }

    input.addEventListener('focus', open);
    input.addEventListener('input', open);
    input.addEventListener('keydown', function (e) {
      if (e.key === 'Enter' || e.key === 'Escape') close();
    });
    input.addEventListener('blur', function () { setTimeout(close, 120); });
    list.addEventListener('click', function (e) {
      var li = e.target.closest('li[data-val]');
      if (li) { input.value = li.getAttribute('data-val'); close(); }
    });
  }

  initCombobox('pr-desc-task', 'pr-cb-task-list', TASK_OPTIONS);
  initCombobox('pr-desc-proc', 'pr-cb-proc-list', PROC_OPTIONS);

  // ---------- 紧急程度 ----------
  // 重要 → 选 x 天内解决；紧急 → 选 x 小时内解决；其余不显示数值
  function syncUrgency() {
    var v = urgencySelect.value;
    if (v === '重要') {
      urgencyUnit.textContent = '天内解决';
      urgencyInput.max = 30;
      urgencyWrap.hidden = false;
    } else if (v === '紧急') {
      urgencyUnit.textContent = '小时内解决';
      urgencyInput.max = 24;
      urgencyWrap.hidden = false;
    } else {
      urgencyWrap.hidden = true;
    }
  }
  urgencySelect.addEventListener('change', syncUrgency);
  syncUrgency();

  function urgencyText() {
    var u = urgencySelect.value;
    if ((u === '重要' || u === '紧急') && !urgencyWrap.hidden) {
      var v = parseInt(urgencyInput.value, 10);
      if (v > 0) return u + '（' + v + (u === '重要' ? ' 天' : ' 小时') + '内解决）';
    }
    return u;
  }

  function labelClustersText() {
    var cs = (map.labelClusters && map.labelClusters[state.label]) || [];
    return cs.length ? cs.join('、') : '未知';
  }

  // ---------- 校验 ----------
  // 第 1 步自查与第 5 步提单人均为可选，不强制；2/3/4 逐步校验必填项
  function validate(step) {
    if (step === 2 && !state.repo) return '请先选择项目（第 2 步）';
    if (step === 3 && !state.label) return '请选择 runs-on 标签（第 3 步）';
    if (step === 4) {
      if (!urlInput.value.trim()) return '请填写问题 URL';
      if (!descProblem.value.trim()) return '请描述出现的问题（第 4 步）';
    }
    return '';
  }

  prevBtn.addEventListener('click', function () {
    if (currentStep > 1) setStep(currentStep - 1);
  });

  nextBtn.addEventListener('click', function () {
    var err = validate(currentStep);
    if (err) { showError(err); return; }
    setStep(currentStep + 1);
  });

  // ---------- Step 4: 摘要 + 生成链接 ----------
  // 决策树路径文本：写入 Issue 正文「自查路径」字段（自助解决登记与转人工提单都带）
  function treePathText() {
    if (!treeData || !treeCurrent || !treePath.length) return '未使用决策树';
    var parts = treePath.map(function (c) { return c.label; });
    var node = treeData.nodes[treeCurrent];
    if (node) {
      parts.push(node.type === 'leaf' ? '命中案例：' + (node.title || '') : '停在问题：' + (node.title || ''));
    }
    return parts.join(' → ');
  }

  function descBullets() {
    var parts = [
      ['任务', descTask.value.trim()],
      ['执行过程', descProc.value.trim()],
      ['出现的问题', descProblem.value.trim()],
      ['预期', descExpected.value.trim()]
    ];
    var lines = parts.filter(function (p) { return p[1]; })
      .map(function (p) {
        // 多行文本缩进两空格，保持在同一列表项内；加粗字段名便于区分
        var v = p[1].replace(/\n+/g, '\n  ');
        return '- **' + p[0] + '**：' + v;
      });
    return lines.length ? lines.join('\n') : '';
  }

  function renderSummary() {
    var rows = [
      ['项目', state.repo],
      ['runs-on 标签', state.label],
      ['对应集群', labelClustersText()],
      ['问题 URL', urlInput.value.trim()],
      ['现象描述', descBullets()],
      ['提单人', reporterInput.value.trim() || '未填写'],
      ['是否正在运行', runningChk.checked ? '是' : '否'],
      ['紧急程度', urgencyText()],
      ['错误信息', errInput.value.trim() || '无'],
      ['是否为已知问题', knownChk.checked ? '是' : '否']
    ];
    summary.innerHTML = '<table class="pr-summary-table">' + rows.map(function (r) {
      return '<tr><th>' + escapeHtml(r[0]) + '</th><td>' +
        escapeHtml(r[1]).replace(/\n/g, '<br>') + '</td></tr>';
    }).join('') + '</table>';
  }

  function buildLink() {
    // 问题 URL：按换行 / 空格 / 中英文逗号 分隔；裸 URL 由 GitHub 自动渲染为可点击链接
    var urls = urlInput.value.trim().split(/[\n\s,，]+/).filter(Boolean);
    var urlText = urls.join('\n');
    var runningText = runningChk.checked ? '是' : '否';
    var knownText = knownChk.checked ? '是' : '否';
    // 概览：开头用紧凑表格一眼看清关键信息
    var overview =
      '| 社区/仓库 | 集群 | 提单人 | 紧急程度 | 运行中 | 已知问题 |\n' +
      '| :--- | :--- | :--- | :--- | :---: | :---: |\n' +
      '| ' + (state.repo || '-') + ' | ' + (labelClustersText() || '-') +
      ' | ' + (reporterInput.value.trim() || '未填写') + ' | ' + urgencyText() +
      ' | ' + runningText + ' | ' + knownText + ' |';
    var jobSection = '';
    if (jobState) {
      var job = jobState.job;
      var badge = jobBadge(job);
      jobSection = [
        '### Job 执行信息（页面自动识别）', '',
        '```text',
        '状态：' + badge.text + '（status=' + (job.status || '-') +
          '，conclusion=' + (job.conclusion || '-') + '）',
        'workflow：' + (job.workflow_name || '-'),
        'job：' + (job.name || '-'),
        'runs-on 标签：' + ((job.labels || []).join(', ') || '-'),
        '推断集群：' + (jobClusters(job).join('、') || '未知（待 pod-history 补全）'),
        'runner：' + (job.runner_name || '(未分配)'),
        '```', ''
      ].join('\n');
    }
    var body = [
      '### 概览', '', overview, '',
      '### 自查路径', '', selfCheckPathText(), '',
      '### runs-on 标签', '', '```\n' + state.label + '\n```', '',
      '### 问题 URL', '', urlText, '',
      jobSection,
      '### 简单描述你看到的现象', '', descBullets(), '',
      '### 错误信息', '', '```bash\n' + (errInput.value.trim() || '无') + '\n```', ''
    ].join('\n');
    // 标题关键短语取「出现的问题」字段，超过 24 字截断加省略号；为空时兜底
    var problem = descProblem.value.trim();
    if (problem.length > 24) problem = problem.slice(0, 24) + '…';
    var title = '[缺陷]: 业务反馈 ' + state.repo + '：' + (problem || '出现问题');
    var qs = new URLSearchParams({
      title: title,
      body: body,
      labels: 'problem-tracking'
    });
    return 'https://github.com/ascend-gha-runners/docs/issues/new?' + qs.toString();
  }

  genBtn.addEventListener('click', function () {
    // 第 1 步为自查（无需必填），2/3/4/5 为必填步骤
    var err = validate(2) || validate(3) || validate(4) || validate(5);
    if (err) { showError(err); setStep(2); return; }
    window.open(buildLink(), '_blank');
    genBtn.disabled = true;
    copyBtn.disabled = true;
    resetBtn.hidden = false;
    result.innerHTML = '<p>已在新标签页打开 GitHub Issue 页面。请检查无误后点击「Submit new issue」完成提交；提交完成后点「重新登记」登记下一个问题。</p>';
  });

  // 重新登记：清空表单回到第 1 步，避免误操作重复打开同一预填链接
  function resetForm() {
    state.repo = '';
    state.label = '';
    repoInput.value = '';
    renderRepos();
    labelSearch.value = '';
    labelOptions.innerHTML = '';
    labelHint.innerHTML = '';
    urlInput.value = '';
    descTask.value = '';
    descProc.value = '';
    descProblem.value = '';
    descExpected.value = '';
    errInput.value = '';
    reporterInput.value = '';
    runningChk.checked = false;
    knownChk.checked = false;
    urgencySelect.value = '一般';
    urgencyWrap.hidden = true;
    summary.innerHTML = '';
    result.innerHTML = '';
    genBtn.disabled = false;
    copyBtn.disabled = false;
    resetBtn.hidden = true;
    jobState = null;
    jobRunJobs = [];
    jobRunUrl = '';
    if (jobUrlInput) jobUrlInput.value = '';
    if (jobResultEl) { jobResultEl.innerHTML = ''; jobResultEl.hidden = true; }
    showEntry('tree');
    treeReset();
    treeRenderNode();
    setStep(1);
  }
  resetBtn.addEventListener('click', resetForm);

  copyBtn.addEventListener('click', function () {
    var link = buildLink();
    if (navigator.clipboard) {
      navigator.clipboard.writeText(link).then(function () {
        copyBtn.textContent = '已复制';
        setTimeout(function () { copyBtn.textContent = '复制链接'; }, 1500);
      }, function () {});
    }
  });

  // ---------- 决策树：渲染与导航 ----------
  function treeReset() {
    leaveLeaf();
    treePath = [];
    treeCurrent = treeData && treeStart ? treeStart : null;
    treeClearSearch();
  }

  function treeRenderPath() {
    if (!treePathEl) return;
    treePathEl.innerHTML = treePath.map(function (c, i) {
      return '<button type="button" class="pr-tree-crumb" data-index="' + i + '">' +
        escapeHtml(c.label) + '</button>';
    }).join('<span class="pr-tree-arrow">→</span>');
  }

  // 叶子归属徽标：badge 值 → 文案与颜色类（淡橙=用户可自查修改，淡蓝=CI 侧处理）
  var LEAF_BADGES = {
    'check-workflow': { text: '检查 workflow', cls: 'pr-leaf-badge--user' },
    'check-resource': { text: '检查资源申请', cls: 'pr-leaf-badge--user' },
    'check-github': { text: '检查 GitHub 配置', cls: 'pr-leaf-badge--user' },
    'ci-infra': { text: '基础设施处理', cls: 'pr-leaf-badge--ci' }
  };

  function leafBadgeHtml(node) {
    var b = node.badge && LEAF_BADGES[node.badge];
    return b ? ' <span class="pr-leaf-badge ' + b.cls + '">' + b.text + '</span>' : '';
  }

  function treeRenderNode() {
    if (!treeNodeEl || !treeData || !treeCurrent) return;
    var node = treeData.nodes[treeCurrent];
    if (!node) return;
    if (leafEnteredId && leafEnteredId !== treeCurrent) leaveLeaf();
    treeRenderPath();

    if (node.type === 'question') {
      var branches = (node.branches || []).map(function (b) {
        return '<button type="button" class="pr-tree-branch" data-to="' +
          escapeHtml(b.to) + '" data-label="' + escapeHtml(b.label) + '">' +
          escapeHtml(b.label) + '</button>';
      }).join('');
      treeNodeEl.innerHTML =
        '<p class="pr-tree-qtitle">' + escapeHtml(node.title || '') + '</p>' +
        (node.text ? '<p class="pr-tree-qtext">' + escapeHtml(node.text) + '</p>' : '') +
        '<div class="pr-tree-branches">' + branches + '</div>';
      return;
    }

    if (node.type === 'leaf') {
      var steps = (node.steps || []).map(function (s) {
        return '<li>' + escapeHtml(s) + '</li>';
      }).join('');
      var links = (node.links || []).map(function (l) {
        return '<a href="' + escapeHtml(l.href) + '" target="_blank" rel="noopener">' +
          escapeHtml(l.text) + '</a>';
      }).join('');
      var rel = relatedLeaves(treeCurrent);
      var relBtn = function (r) {
        // 把「为什么推荐它」写进 title，鼠标悬停可看共同的报错关键词，避免莫名推荐
        var why = (r.shared && r.shared.length)
          ? ' title="共同报错关键词：' + escapeHtml(r.shared.join('、')) + '"' : '';
        return '<button type="button" class="pr-tree-branch pr-related" data-leaf="' +
          escapeHtml(r.leafId) + '"' + why + '>' + escapeHtml(r.leaf.title || '') + leafBadgeHtml(r.leaf) +
          '</button>';
      };
      var relSimilar = rel.similar.map(relBtn).join('');
      var relSameCat = rel.sameCat.map(relBtn).join('');
      var relatedHtml = '';
      if (relSimilar) {
        relatedHtml += '<p class="pr-leaf-related-title">报错关键词相近的案例（不是这个？点一下换一个）</p>' +
          '<div class="pr-tree-branches">' + relSimilar + '</div>';
      }
      if (relSameCat) {
        relatedHtml += '<p class="pr-leaf-related-title">同分类下的其它案例</p>' +
          '<div class="pr-tree-branches">' + relSameCat + '</div>';
      }
      treeNodeEl.innerHTML =
        '<div class="pr-leaf">' +
          '<p class="pr-leaf-title">' + escapeHtml(node.title || '') +
            leafBadgeHtml(node) +
          '</p>' +
          '<p class="pr-leaf-summary">' + escapeHtml(node.summary || '') + '</p>' +
          (steps ? '<ol class="pr-leaf-steps">' + steps + '</ol>' : '') +
          (links ? '<div class="pr-leaf-links">' + links + '</div>' : '') +
          (relatedHtml ? '<div class="pr-leaf-related">' + relatedHtml + '</div>' : '') +
          '<div class="pr-leaf-actions">' +
            '<button type="button" class="pr-btn pr-btn-sm pr-leaf-solved">已解决（顺手登记，可选）</button>' +
            '<button type="button" class="pr-link-btn pr-leaf-joblink">仍未解决？用失败的 Job 链接再查一次 →</button>' +
          '</div>' +
        '</div>';
      leafEnteredId = treeCurrent;
      leafEnteredAt = Date.now();
      track('leaf_view', {
        leaf: treeCurrent,
        from: treeSearchTerm ? 'search' : (treeJobRef ? 'job' : 'manual'),
        q: treeSearchTerm,
        depth: treePath.length
      });
    }
  }

  // ---------- 决策树：报错关键词搜索 ----------
  // 索引纯前端由决策树派生（不改 problem-tree.json）：对每条 根→叶子 路径，
  // 拼出叶子 title + summary + steps + symptoms + 各级分叉标签 + 沿途问题节点标题作为可检索文本。
  // 同时为每个叶子建相似度 token 集（英文词 + 中文二元组），用于「相似案例」推荐。

  // 报错原文 / 错误码 → 决策树里的说法，解决「贴日志搜不到」的问题
  var SEARCH_SYNONYMS = [
    { keys: ['207001', 'aclrtmallochost', 'host内存', 'host 内存'], terms: ['host 内存不足'] },
    { keys: ['137', 'poststart'], terms: ['容器启动即死'] },
    { keys: ['401', 'unauthorized'], terms: ['401'] },
    { keys: ['econnrefused', 'selfsubjectaccessreviews', '控制面'], terms: ['控制面 api 瞬断'] },
    { keys: ['keyerror', 'weight_offset'], terms: ['模型缓存缺失', '缓存版本'] },
    { keys: ['outofcpu'], terms: ['调度失败'] },
    { keys: ['podinitializing', 'initialize containers'], terms: ['镜像拉取慢'] },
    { keys: ['oomkilled', 'oom'], terms: ['内存不足'] },
    { keys: ['could not resolve host', 'nxdomain'], terms: ['节点异常'] },
    { keys: ['failedmount', 'hostpath'], terms: ['节点维护后异常'] },
    { keys: ['parent snapshot'], terms: ['构建缓存损坏'] },
    { keys: ['crates.io', 'hashes from the requirements'], terms: ['依赖缓存异常'] }
  ];

  function expandSynonyms(q) {
    var lower = String(q).toLowerCase();
    var out = [];
    SEARCH_SYNONYMS.forEach(function (m) {
      if (m.keys.some(function (k) { return lower.indexOf(k) !== -1; })) {
        out = out.concat(m.terms);
      }
    });
    return out;
  }

  // 相似案例只认「强标识」错误词：CamelCase（ErrImagePull）、全大写（OOMKilled）、含数字（207001、137）。
  // 不按中文词面比对，避免「失败/异常」这类高频词把不相关案例推上来。
  var STRONG_STOP = { github: 1, kubernetes: 1, namespace: 1, workflow: 1 };
  var STRONG_MAX_DF = 8;   // 出现在超过 8 个案例里的词没有区分度，直接忽略
  var treeDf = {};
  var relatedCount = { similar: 3, sameCat: 3 };

  function strongTokens(text) {
    var set = {};
    var m = String(text).match(/[A-Za-z][A-Za-z0-9_.-]{3,}/g) || [];
    m.forEach(function (w) {
      if (!/[a-z][A-Z]/.test(w) && !/^[A-Z0-9_.-]+$/.test(w) && !/[0-9]/.test(w)) return;
      var k = w.toLowerCase();
      if (!STRONG_STOP[k]) set[k] = 1;
    });
    return set;
  }

  function buildTreeIndex() {
    treeIndex = [];
    if (!treeData || !treeStart) return;
    (function walk(nodeId, path, trailTitles) {
      var node = treeData.nodes[nodeId];
      if (!node) return;
      if (node.type === 'leaf') {
        var parts = [node.title || '', node.summary || '']
          .concat(node.steps || [])
          .concat(node.symptoms || [])
          .concat(path.map(function (c) { return c.label; }))
          .concat(trailTitles);
        var text = parts.join('\n').toLowerCase();
        treeIndex.push({
          path: path.slice(),
          leafId: nodeId,
          leaf: node,
          text: text,
          strong: strongTokens(parts.join('\n'))
        });
        return;
      }
      (node.branches || []).forEach(function (b) {
        walk(b.to, path.concat([{ from: nodeId, label: b.label, to: b.to }]),
          trailTitles.concat([node.title || '']));
      });
    })(treeStart, [], []);
    treeDf = {};
    treeIndex.forEach(function (h) {
      Object.keys(h.strong).forEach(function (k) { treeDf[k] = (treeDf[k] || 0) + 1; });
    });
  }

  // 相似案例两组：
  //   similar  = 与该叶子共享「强标识错误词」的其它案例（按共享词多少排序）
  //   sameCat  = 同一分类（同一个上级问题）下的其它案例，作为兜底，保证叶子不「孤立无援」
  function relatedLeaves(nodeId) {
    var mine = null;
    treeIndex.forEach(function (h) { if (h.leafId === nodeId) mine = h; });
    if (!mine) return { similar: [], sameCat: [] };
    var myParent = mine.path.length ? mine.path[mine.path.length - 1].from : '';
    var scored = [];
    treeIndex.forEach(function (h) {
      if (h.leafId === nodeId) return;
      var shared = [];
      Object.keys(mine.strong).forEach(function (k) {
        if (h.strong[k] && treeDf[k] <= STRONG_MAX_DF) shared.push(k);
      });
      scored.push({
        h: h,
        shared: shared,
        n: shared.length,
        parent: h.path.length ? h.path[h.path.length - 1].from : ''
      });
    });
    var similar = scored.filter(function (x) { return x.n > 0; })
      .sort(function (a, b) { return b.n - a.n; })
      .slice(0, relatedCount.similar);
    var used = {};
    similar.forEach(function (x) { used[x.h.leafId] = 1; });
    var sameCat = scored.filter(function (x) {
      return myParent && x.parent === myParent && !used[x.h.leafId];
    }).sort(function (a, b) { return b.n - a.n; })
      .slice(0, relatedCount.sameCat);
    return {
      similar: similar.map(function (x) { return { leafId: x.h.leafId, leaf: x.h.leaf, shared: x.shared }; }),
      sameCat: sameCat.map(function (x) { return { leafId: x.h.leafId, leaf: x.h.leaf, shared: x.shared }; })
    };
  }

  // 手动逐级导航时放弃搜索态，避免「搜索命中」指标串味
  function treeClearSearch() {
    treeSearchTerm = '';
    treeJobRef = '';
    if (treeSearchEl) treeSearchEl.value = '';
    hideTreeResults();
  }

  function hideTreeResults() {
    if (!treeResultsEl) return;
    treeResultsEl.hidden = true;
    treeResultsEl.innerHTML = '';
  }

  // 候选里展示完整链路，让用户未点选也能先看清走到哪
  function treeHitPathText(hit) {
    return hit.path.map(function (c) { return c.label; })
      .concat(['命中案例：' + (hit.leaf.title || '')]).join(' → ');
  }

  // 直达：面包屑填满整条路径并渲染叶子案例卡；记录关键词供「已解决」登记打标
  function treeGotoHit(hit, term) {
    treePath = hit.path.slice();
    treeCurrent = hit.leafId;
    treeSearchTerm = term;
    hideTreeResults();
    treeRenderNode();
  }

  function treeResultHtml(h) {
    return '<button type="button" class="pr-tree-result" data-leaf="' + escapeHtml(h.leafId) + '">' +
      '<span class="pr-tree-result-title">' + escapeHtml(h.leaf.title || '') + '</span>' +
      '<span class="pr-tree-result-path">' + escapeHtml(treeHitPathText(h)) + '</span>' +
    '</button>';
  }

  // 搜索埋点做 900ms 去抖，避免逐字输入刷出大量事件
  function trackSearch(q, hits, near) {
    clearTimeout(searchTrackTimer);
    searchTrackTimer = setTimeout(function () {
      track(hits ? 'search' : 'search_miss', { q: q, hits: hits, near: near });
    }, 900);
  }

  function runTreeSearch() {
    if (!treeSearchEl || !treeResultsEl || !treeData) return;
    var q = treeSearchEl.value.trim();
    if (!q) {  // 清空搜索：回到正常逐级导航
      treeSearchTerm = '';
      hideTreeResults();
      treeRenderNode();
      return;
    }
    var tokens = tokenizeSearch(q);
    var syn = expandSynonyms(q);
    // 同义词命中：日志里的错误码 / 报错原文能对到决策树里的说法
    var hits = treeIndex.filter(function (h) {
      return matchesAllSearch(tokens, h.text) ||
        syn.some(function (s) { return h.text.indexOf(s.toLowerCase()) !== -1; });
    });
    if (hits.length === 1) {  // 单命中：直接出整条链路
      treeGotoHit(hits[0], q);
      trackSearch(q, 1, 0);
      return;
    }
    treeSearchTerm = '';  // 还没选定目标，不算搜索命中
    if (!hits.length) {
      // 无完全匹配时给最相近的 3 个，避免用户直接放弃
      var near = treeIndex.map(function (h) {
        var n = 0;
        tokens.forEach(function (t) { if (h.text.indexOf(t) !== -1) n++; });
        return { h: h, n: n };
      }).filter(function (x) { return x.n > 0; })
        .sort(function (a, b) { return b.n - a.n; })
        .slice(0, 3);
      trackSearch(q, 0, near.length);
      treeResultsEl.innerHTML = near.length
        ? '<p class="pr-tree-noresult">没有完全匹配的案例，以下可能是相近问题：</p>' +
          near.map(function (x) { return treeResultHtml(x.h); }).join('')
        : '<p class="pr-tree-noresult">无匹配案例，可继续逐级点选，或直接点「下一步」登记。</p>';
      treeResultsEl.hidden = false;
      return;
    }
    trackSearch(q, hits.length, 0);
    treeResultsEl.innerHTML = hits.map(treeResultHtml).join('');
    treeResultsEl.hidden = false;
  }

  if (treeSearchEl) {
    treeSearchEl.addEventListener('input', runTreeSearch);
    treeSearchEl.addEventListener('search', runTreeSearch);  // 点击原生 x 清空时同步更新
  }

  if (treeResultsEl) {
    treeResultsEl.addEventListener('click', function (e) {
      var btn = e.target.closest('.pr-tree-result');
      if (!btn) return;
      var leafId = btn.getAttribute('data-leaf');
      var hit = null;
      treeIndex.forEach(function (h) { if (!hit && h.leafId === leafId) hit = h; });
      if (hit) treeGotoHit(hit, treeSearchEl.value.trim());
    });
  }

  // ---------- 自助解决登记（自愿，仅统计用） ----------
  // 自查路径：来自搜索命中时前缀标注关键词，便于周统计区分「逐级点选」与「搜索命中」来源
  // 提单里的「自查路径」：走 Job 路径时没有决策树路径，用 Job 链接 + 命中案例兜底
  function selfCheckPathText() {
    if (jobState) {
      var node = (jobState.leafId && treeData) ? treeData.nodes[jobState.leafId] : null;
      return 'Job 匹配：' + jobState.url + (node ? ' → ' + (node.title || '') : '（未匹配到案例）');
    }
    var p = treePathText();
    return p || '（未使用决策树）';
  }

  function solvedPathText() {
    var t = treePathText();
    if (treeJobRef) return 'Job 匹配：' + treeJobRef + ' → ' + t;
    return treeSearchTerm ? '搜索命中：' + treeSearchTerm + ' → ' + t : t;
  }

  function buildSolvedLink() {
    var node = (treeData && treeCurrent) ? treeData.nodes[treeCurrent] : null;
    var leafTitle = (node && node.type === 'leaf') ? (node.title || '') : '';
    var body = [
      '> 自愿登记：仅用于统计自助解决率与改进决策树，不会有人处理，可不留名，直接 Submit 即可；不想登记关闭本页即可。', '',
      '### 自查路径', '', solvedPathText(), '',
      '### 命中案例', '', leafTitle || '（无）', '',
      '### 备注（可选）', '', '（哪一步帮你解决了问题，或案例步骤哪里不准确）'
    ].join('\n');
    var title = '[自助解决]: ' + (leafTitle || '决策树自助解决');
    if (title.length > 80) title = title.slice(0, 80) + '…';
    var qs = new URLSearchParams({
      title: title,
      body: body,
      labels: 'self-resolved'
    });
    return 'https://github.com/ascend-gha-runners/docs/issues/new?' + qs.toString();
  }

  if (treeNodeEl) {
    treeNodeEl.addEventListener('click', function (e) {
      // 相似案例：直接跳到目标叶子
      var related = e.target.closest('.pr-related');
      if (related) {
        var relLeaf = related.getAttribute('data-leaf');
        var relHit = null;
        treeIndex.forEach(function (h) { if (!relHit && h.leafId === relLeaf) relHit = h; });
        if (relHit) {
          track('related_click', { from: treeCurrent, to: relLeaf });
          leaveLeaf();
          treeGotoHit(relHit, '');
        }
        return;
      }
      var branch = e.target.closest('.pr-tree-branch');
      if (branch) {
        leaveLeaf();
        treeClearSearch();
        treePath.push({
          from: treeCurrent,
          label: branch.getAttribute('data-label'),
          to: branch.getAttribute('data-to')
        });
        treeCurrent = branch.getAttribute('data-to');
        treeRenderNode();
        return;
      }
      if (e.target.closest('.pr-leaf-joblink')) {
        track('goto_job', { leaf: treeCurrent, q: treeSearchTerm });
        leaveLeaf();
        showEntry('job');
        if (jobUrlInput) jobUrlInput.focus();
        return;
      }
      if (e.target.closest('.pr-leaf-solved')) {
        track('solved_click', { leaf: treeCurrent, q: treeSearchTerm, ms: Date.now() - leafEnteredAt });
        leaveLeaf();
        window.open(buildSolvedLink(), '_blank');
        treeReset();
        treeRenderNode();
      }
    });
  }

  if (treePathEl) {
    treePathEl.addEventListener('click', function (e) {
      var crumb = e.target.closest('.pr-tree-crumb');
      if (!crumb) return;
      var idx = parseInt(crumb.getAttribute('data-index'), 10);
      if (isNaN(idx) || !treePath[idx]) return;
      leaveLeaf();
      treeClearSearch();
      treeCurrent = treePath[idx].from;
      treePath = treePath.slice(0, idx);
      treeRenderNode();
    });
  }

  // ---------- Job 链接识别（只读 GitHub 公开接口） ----------
  // 数据只来自 https://api.github.com/repos/{repo}/actions/jobs/{id}：
  // 状态、结论、workflow/job 名、runs-on 标签、runner 名。
  // 「实际执行集群 / Pod 历史」来自 pod-history 接口，浏览器跨域与证书都过不去，这里不做；
  // 由提 issue 后的自动分析工作流补全。
  var jobUrlInput = $('pr-job-url');
  var jobBtn = $('pr-job-btn');
  var jobResultEl = $('pr-job-result');
  var jobRunJobs = [];   // run 链接模式下，该次运行的 job 列表
  var jobRunUrl = '';

  // 第 1 步两个入口：① Job 链接 ② 报错/现象
  var entryTabs = document.querySelectorAll('.pr-tab[data-entry]');
  var entryPanels = { job: $('pr-entry-job'), tree: $('pr-entry-tree') };

  function showEntry(name) {
    entryTabs.forEach(function (b) {
      b.classList.toggle('is-active', b.getAttribute('data-entry') === name);
    });
    Object.keys(entryPanels).forEach(function (k) {
      if (entryPanels[k]) entryPanels[k].hidden = (k !== name);
    });
  }

  entryTabs.forEach(function (b) {
    b.addEventListener('click', function () { showEntry(b.getAttribute('data-entry')); });
  });

  var JOB_STATUS = {
    queued: { text: '排队中（尚未分配 runner）', cls: 'pr-job-badge--wait' },
    waiting: { text: '等待中', cls: 'pr-job-badge--wait' },
    pending: { text: '等待中', cls: 'pr-job-badge--wait' },
    requested: { text: '等待中', cls: 'pr-job-badge--wait' },
    in_progress: { text: '执行中', cls: 'pr-job-badge--run' }
  };
  var JOB_CONCLUSION = {
    success: { text: '成功', cls: 'pr-job-badge--ok' },
    failure: { text: '失败', cls: 'pr-job-badge--fail' },
    timed_out: { text: '超时', cls: 'pr-job-badge--fail' },
    cancelled: { text: '已取消', cls: 'pr-job-badge--wait' },
    skipped: { text: '已跳过', cls: 'pr-job-badge--wait' },
    action_required: { text: '需要人工处理', cls: 'pr-job-badge--wait' },
    neutral: { text: '已结束（neutral）', cls: 'pr-job-badge--wait' }
  };

  function parseJobUrl(url) {
    var m = String(url || '').match(
      /github\.com\/([^/\s]+)\/([^/\s]+)\/actions\/runs\/(\d+)(?:\/job\/(\d+))?/);
    if (!m) return null;
    return { repo: m[1] + '/' + m[2], runId: m[3], jobId: m[4] || '' };
  }

  // 状态徽标：未结束看 status，已结束看 conclusion
  function jobBadge(job) {
    if (job.status && job.status !== 'completed') {
      return JOB_STATUS[job.status] || { text: job.status, cls: 'pr-job-badge--wait' };
    }
    return JOB_CONCLUSION[job.conclusion] || { text: job.conclusion || '已完成', cls: 'pr-job-badge--wait' };
  }

  // 集群：标签 → Cluster.md 映射；没有标签映射时用 runner 名里的 -cn12-001- 段兜底
  function jobClusters(job) {
    var out = [];
    (job.labels || []).forEach(function (l) {
      ((map && map.labelClusters && map.labelClusters[l]) || []).forEach(function (c) {
        if (out.indexOf(c) === -1) out.push(c);
      });
    });
    if (!out.length && job.runner_name) {
      var m = String(job.runner_name).match(/-([a-z0-9]+-\d+)-[a-z0-9]+-runner-[a-z0-9]+$/);
      if (m) out.push(m[1] + '（按 runner 名推断）');
    }
    return out;
  }

  function jobSearchQuery(job) {
    // 失败步骤名往往比 job 名更有信息量（如 "Upload logs" / "Build wheel"）
    var failedSteps = (job.steps || [])
      .filter(function (s) { return s.conclusion === 'failure'; })
      .map(function (s) { return s.name || ''; });
    return [job.name || '', job.workflow_name || '', (job.labels || []).join(' '),
      job.conclusion || ''].concat(failedSteps).join(' ');
  }

  // 命中数排序（不像搜索框那样要求全部关键词命中，Job 名通常带很多无关词）；
  // minScore 默认 2：只命中一个泛词时不推荐，避免把不相关案例推给用户
  function treeRankedHits(q, limit, minScore) {
    var tokens = tokenizeSearch(q).filter(function (t) { return t.length >= 3; });
    if (!tokens.length) return [];
    var floor = typeof minScore === 'number' ? minScore : 2;
    return treeIndex.map(function (h) {
      var n = 0;
      tokens.forEach(function (t) { if (h.text.indexOf(t) !== -1) n++; });
      return { h: h, n: n };
    }).filter(function (x) { return x.n >= floor; })
      .sort(function (a, b) { return b.n - a.n; })
      .slice(0, limit)
      .map(function (x) { return x.h; });
  }

  function jobTimeText(job) {
    function fmt(s) {
      if (!s) return '';
      try { return new Date(s).toLocaleString('zh-CN', { hour12: false }); } catch (e) { return s; }
    }
    var a = fmt(job.started_at || job.created_at);
    var b = job.completed_at ? fmt(job.completed_at) : '进行中';
    return a ? a + ' → ' + b : '';
  }

  function renderJob() {
    if (!jobState || !jobResultEl) return;
    var job = jobState.job;
    var badge = jobBadge(job);
    var clusters = jobClusters(job);
    var labels = (job.labels || []).join(', ');
    var hits = treeRankedHits(jobSearchQuery(job), 3);
    var failedSteps = (job.steps || [])
      .filter(function (s) { return s.conclusion === 'failure'; })
      .map(function (s) { return s.name || ''; })
      .filter(Boolean);
    var kvRows = [
      ['仓库', jobState.repo],
      ['workflow', job.workflow_name || '-'],
      ['job', job.name || '-'],
      ['runs-on 标签', labels || '-'],
      ['推断集群', clusters.join('、') || '未知'],
      ['runner', job.runner_name || '(未分配)'],
      ['时间', jobTimeText(job) || '-']
    ];
    if (failedSteps.length) kvRows.push(['失败步骤', failedSteps.join('、')]);
    // 两列对齐（标签列宽自适应，值列左对齐），比「标签：值」的参差排版更好读
    var kv = '<div class="pr-job-kv-grid">' + kvRows.map(function (r) {
      return '<span class="pr-job-k">' + escapeHtml(r[0]) + '</span>' +
        '<span class="pr-job-v">' + escapeHtml(r[1]) + '</span>';
    }).join('') + '</div>';

    var hitsHtml = hits.length
      ? '<p class="pr-job-note">按 job 名 / 失败步骤 / 标签匹配到的案例（点开看步骤）：</p>' +
        hits.map(function (h) {
          return '<button type="button" class="pr-tree-result pr-job-hit" data-leaf="' + escapeHtml(h.leafId) + '">' +
            '<span class="pr-tree-result-title">' + escapeHtml(h.leaf.title || '') + '</span>' +
            '<span class="pr-tree-result-path">' + escapeHtml(treeHitPathText(h)) + '</span>' +
          '</button>';
        }).join('')
      : '<p class="pr-job-note">job 名和标签里没有可识别的报错关键词，没法可靠匹配案例。' +
        '建议把日志里的报错粘到下面搜索框，或直接用这个 job 填单。</p>';

    var note = '';
    if (job.status !== 'completed') {
      note = '任务还没结束，提单时会自动勾选「是否正在运行」。';
    } else if (job.conclusion === 'success') {
      note = '这个 job 是成功的；如果问题出现在别的 job，换一个链接再识别。';
    }

    var leafNode = (jobState.leafId && treeData && treeData.nodes[jobState.leafId])
      ? treeData.nodes[jobState.leafId] : null;

    jobResultEl.innerHTML =
      '<p class="pr-job-kv"><span class="pr-job-badge ' + badge.cls + '">' + escapeHtml(badge.text) + '</span>　' +
        escapeHtml(job.name || '') + '</p>' +
      '<div class="pr-job-kv">' + kv + '</div>' +
      (note ? '<p class="pr-job-note">' + escapeHtml(note) + '</p>' : '') +
      '<div class="pr-tree-results pr-job-hits">' + hitsHtml + '</div>' +
      (leafNode ? jobLeafHtml(leafNode) : '') +
      '<div class="pr-job-actions">' +
        '<button type="button" class="pr-btn pr-btn-sm" id="pr-job-solved">已解决，生成查看解决记录</button>' +
        '<a class="pr-btn pr-btn-sm pr-btn-ghost" href="' + escapeHtml(job.html_url || jobState.url) +
          '" target="_blank" rel="noopener">查看原任务</a>' +
        '<button type="button" class="pr-btn pr-btn-sm pr-btn-ghost" id="pr-job-fill">根据任务信息提单</button>' +
      '</div>' +
      '<p class="pr-job-note">日志正文 GitHub 接口拿不到（需登录且跨域受限）：点「查看原任务」看失败步骤日志，' +
        '把报错粘到「根据报错信息和现象」里搜索会更准。</p>';
    jobResultEl.hidden = false;
  }

  function queryJob() {
    if (!jobUrlInput || !jobResultEl) return;
    var url = jobUrlInput.value.trim();
    var parsed = parseJobUrl(url);
    if (!parsed) {
      jobResultEl.innerHTML = '<p class="pr-job-note">无法识别链接，请粘贴 Actions 页面的地址，' +
        '形如 .../actions/runs/123456/job/789012 或 .../actions/runs/123456。</p>';
      jobResultEl.hidden = false;
      return;
    }
    if (parsed.jobId) fetchJob(parsed.repo, parsed.jobId, url);
    else loadRunJobs(parsed, url);   // 只给了 run 链接：先列出该次运行的 job
  }

  function jobFetchError(r) {
    if (r.status === 404) return '读不到这个任务：仓库可能是私有的，或链接里的编号不对。可直接手动填单。';
    if (r.status === 403 || r.status === 429) return 'GitHub 匿名接口限流了（每小时 60 次），稍后再试或直接手动填单。';
    if (r.status === 422) return 'GitHub 接口拒绝了这次查询（编号可能已过期），可手动填单。';
    return 'GitHub 接口返回 ' + r.status + '，可直接手动填单。';
  }

  function fetchJob(repo, jobId, url) {
    jobResultEl.innerHTML = '<p class="pr-job-note">正在查询 GitHub…</p>';
    jobResultEl.hidden = false;
    fetch('https://api.github.com/repos/' + repo + '/actions/jobs/' + jobId,
      { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) {
        if (!r.ok) throw new Error(jobFetchError(r));
        return r.json();
      })
      .then(function (job) {
        jobState = { url: job.html_url || url, repo: repo, job: job };
        renderJob();
        track('job_query', { status: job.status, conclusion: job.conclusion, repo: repo });
      })
      .catch(function (err) {
        jobState = null;
        jobResultEl.innerHTML = '<p class="pr-job-note">' + escapeHtml(err.message) + '</p>';
      });
  }

  // run 链接：列出该次运行下所有 job（失败的排前面），点一个再看详情
  function loadRunJobs(parsed, url) {
    jobResultEl.innerHTML = '<p class="pr-job-note">这是整条 run 的链接，正在列出这次运行的 job…</p>';
    jobResultEl.hidden = false;
    fetch('https://api.github.com/repos/' + parsed.repo + '/actions/runs/' + parsed.runId + '/jobs?per_page=100',
      { headers: { Accept: 'application/vnd.github+json' } })
      .then(function (r) {
        if (!r.ok) throw new Error(jobFetchError(r));
        return r.json();
      })
      .then(function (data) {
        var jobs = (data && data.jobs) || [];
        if (!jobs.length) throw new Error('这条 run 下没有查到 job，可换成具体 job 的链接再试。');
        var bad = jobs.filter(function (j) {
          return j.conclusion === 'failure' || j.conclusion === 'timed_out' || j.conclusion === 'cancelled';
        });
        var rest = jobs.filter(function (j) { return bad.indexOf(j) === -1; });
        jobRunJobs = bad.concat(rest);
        jobRunUrl = url;
        renderJobPicker(parsed.repo);
        track('job_run_query', { repo: parsed.repo, jobs: jobs.length, failed: bad.length });
      })
      .catch(function (err) {
        jobResultEl.innerHTML = '<p class="pr-job-note">' + escapeHtml(err.message) + '</p>';
      });
  }

  function renderJobPicker(repo) {
    jobResultEl.innerHTML =
      '<p class="pr-job-note">这条 run 共 ' + jobRunJobs.length + ' 个 job（失败的排在前面），点一个看详情：</p>' +
      '<div class="pr-job-pick">' + jobRunJobs.map(function (j) {
        var b = jobBadge(j);
        return '<button type="button" class="pr-tree-result pr-job-choose" data-job="' + escapeHtml(String(j.id)) + '">' +
          '<span class="pr-tree-result-title">' + escapeHtml(j.name || '') +
            ' <span class="pr-job-badge ' + b.cls + '">' + escapeHtml(b.text) + '</span></span>' +
          '<span class="pr-tree-result-path">' + escapeHtml(((j.labels || []).join(', ')) || '无标签') + '</span>' +
        '</button>';
      }).join('') + '</div>';
    jobResultEl.setAttribute('data-repo', repo);
  }

  if (jobBtn) jobBtn.addEventListener('click', queryJob);
  if (jobUrlInput) {
    jobUrlInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') { e.preventDefault(); queryJob(); }
    });
  }

  if (jobResultEl) {
    jobResultEl.addEventListener('click', function (e) {
      // run 链接模式：选中某个 job
      var choose = e.target.closest('.pr-job-choose');
      if (choose) {
        var jobId = choose.getAttribute('data-job');
        var picked = null;
        jobRunJobs.forEach(function (j) { if (String(j.id) === jobId) picked = j; });
        if (picked) {
          jobState = {
            url: picked.html_url || jobRunUrl,
            repo: jobResultEl.getAttribute('data-repo') || '',
            job: picked
          };
          renderJob();
        }
        return;
      }
      // 匹配案例：就在这一块展开案例步骤，不跳去决策树
      var hitBtn = e.target.closest('.pr-job-hit');
      if (hitBtn) {
        var leafId = hitBtn.getAttribute('data-leaf');
        if (jobState) {
          jobState.leafId = (jobState.leafId === leafId) ? '' : leafId;   // 再点一次收起
          track('job_match_click', { leaf: leafId });
          renderJob();
          var leafEl = jobResultEl.querySelector('.pr-job-leaf');
          if (leafEl) leafEl.scrollIntoView({ block: 'nearest' });
        }
        return;
      }
      if (e.target.closest('#pr-job-solved')) {
        track('job_solved_click', { repo: jobState ? jobState.repo : '' });
        window.open(buildJobSolvedLink(), '_blank');
        return;
      }
      if (e.target.closest('#pr-job-fill')) fillFromJob();
    });
  }

  // 在 Job 卡片内直接渲染案例详情（复用决策树叶子的排版）
  function jobLeafHtml(node) {
    var steps = (node.steps || []).map(function (s) {
      return '<li>' + escapeHtml(s) + '</li>';
    }).join('');
    var links = (node.links || []).map(function (l) {
      return '<a href="' + escapeHtml(l.href) + '" target="_blank" rel="noopener">' +
        escapeHtml(l.text) + '</a>';
    }).join('');
    return '<div class="pr-leaf pr-job-leaf">' +
      '<p class="pr-leaf-title">' + escapeHtml(node.title || '') + leafBadgeHtml(node) + '</p>' +
      '<p class="pr-leaf-summary">' + escapeHtml(node.summary || '') + '</p>' +
      (steps ? '<ol class="pr-leaf-steps">' + steps + '</ol>' : '') +
      (links ? '<div class="pr-leaf-links">' + links + '</div>' : '') +
      '<p class="pr-job-note">按这个案例解决了，就点「已解决，生成查看解决记录」；没解决就点「根据任务信息提单」。</p>' +
    '</div>';
  }

  // 「已解决」登记：把任务信息与命中案例按报表格式写进 self-resolved issue，便于统计与修正案例
  function buildJobSolvedLink() {
    var job = (jobState && jobState.job) || {};
    var node = (jobState && jobState.leafId && treeData) ? treeData.nodes[jobState.leafId] : null;
    var leaf = (node && node.type === 'leaf') ? node : null;
    var steps = leaf ? (leaf.steps || []) : [];
    var failedSteps = (job.steps || [])
      .filter(function (s) { return s.conclusion === 'failure'; })
      .map(function (s) { return s.name || ''; })
      .filter(Boolean);

    function cell(v) { return String(v == null ? '-' : v).replace(/\|/g, '\\|'); }
    function table(rows) {
      return ['| 字段 | 值 |', '| --- | --- |'].concat(rows.map(function (r) {
        return '| ' + cell(r[0]) + ' | ' + cell(r[1]) + ' |';
      })).join('\n');
    }

    var body = [
      '### 任务执行信息', '',
      table([
        ['仓库', jobState.repo],
        ['workflow', job.workflow_name || '-'],
        ['job', job.name || '-'],
        ['状态', jobBadge(job).text + '（status=' + (job.status || '-') + '，conclusion=' + (job.conclusion || '-') + '）'],
        ['失败步骤', failedSteps.join('、') || '无'],
        ['runs-on 标签', (job.labels || []).join(', ') || '-'],
        ['推断集群', jobClusters(job).join('、') || '未知'],
        ['runner', job.runner_name || '(未分配)'],
        ['Job 链接', job.html_url || jobState.url]
      ]),
      '',
      '### 命中案例', '',
      table([
        ['案例', leaf ? leaf.title : '无（按任务信息自行判断）'],
        ['现象', leaf ? (leaf.summary || '-') : '-']
      ])
    ];
    if (steps.length) {
      body = body.concat(['', '**案例步骤**：', '',
        steps.map(function (s, i) { return (i + 1) + '. ' + s; }).join('\n')]);
    }
    body = body.concat(['', '### 解决方式（可选，写一句能帮我们修正案例）', '', '']);
    var title = '[自助解决]: ' + jobProblemText(job);
    if (title.length > 120) title = title.slice(0, 120) + '…';
    return 'https://github.com/ascend-gha-runners/docs/issues/new?' + new URLSearchParams({
      title: title,
      body: body.join('\n'),
      labels: 'self-resolved'
    }).toString();
  }

  // 用 job 预填：项目、标签、Job 链接、任务类型、执行过程、是否运行中
  function fillFromJob() {
    if (!jobState) return;
    var job = jobState.job;
    var repo = jobState.repo;
    repoInput.value = repo;
    if (map && map.repos && map.repos[repo]) selectRepo(repo);
    else selectOtherRepo();

    var avail = (map && map.repos && map.repos[repo]) || [];
    var pick = (job.labels || []).filter(function (l) { return avail.indexOf(l) !== -1; })[0] ||
      (job.labels || [])[0] || '';
    if (pick) selectLabel(pick);

    urlInput.value = jobState.url;
    descTask.value = pickTaskType(job) || (job.name || '');
    descProc.value = pickProc(job);
    descProblem.value = jobProblemText(job);
    runningChk.checked = job.status !== 'completed';
    treeJobRef = jobState.url;
    track('job_fill', { status: job.status, repo: repo });
    setStep(4);
  }

  // 自动生成「出现的问题」，用户只补现象，不用自己组织句子
  function jobProblemText(job) {
    var failed = (job.steps || [])
      .filter(function (s) { return s.conclusion === 'failure'; })
      .map(function (s) { return s.name || ''; })
      .filter(Boolean);
    var wf = job.workflow_name || 'workflow';
    var jn = job.name || 'job';
    if (failed.length) {
      return '[' + wf + '] 的 [' + jn + '] 任务中步骤 [' + failed.join('、') + '] 失败';
    }
    if (job.status && job.status !== 'completed') {
      return '[' + wf + '] 的 [' + jn + '] 任务一直处于「' + jobBadge(job).text + '」状态，长时间未结束';
    }
    return '[' + wf + '] 的 [' + jn + '] 任务执行' + (jobBadge(job).text || '失败');
  }

  function pickTaskType(job) {
    var s = ((job.name || '') + ' ' + (job.workflow_name || '')).toLowerCase();
    if (s.indexOf('main2main') !== -1) return 'main2main';
    if (s.indexOf('nightly') !== -1) return 'Nightly';
    if (s.indexOf('accuracy') !== -1) return 'Accuracy精度';
    if (s.indexOf('function') !== -1) return 'function功能';
    if (s.indexOf('test') !== -1) return 'Test测试';
    return '';
  }

  function pickProc(job) {
    if (job.status && job.status !== 'completed') {
      return job.status === 'in_progress' ? 'Running运行' : 'Queued排队';
    }
    if (job.conclusion === 'cancelled') return 'Cancelled取消';
    if (job.conclusion === 'failure' || job.conclusion === 'timed_out') return 'Error错误';
    return '';
  }

  // ---------- 初始化 ----------
  fetch('../assets/problem-labels.json', { cache: 'no-store' })
    .then(function (r) { return r.json(); })
    .then(function (data) {
      map = data || { repos: {} };
      renderRepos();
    })
    .catch(function () {
      renderRepos();
    });

  if (treeContainer && treeNodeEl) {
    fetch(TREE_URL, { cache: 'no-store' })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        treeData = data || null;
        treeStart = treeData && treeData.start ? treeData.start : null;
        buildTreeIndex();
        treeReset();
        treeRenderNode();
      })
      .catch(function () {
        treeNodeEl.innerHTML = '<p class="pr-hint">自助决策树加载失败，可直接点「下一步」继续登记。</p>';
      });
  }

  setStep(1);
})();
