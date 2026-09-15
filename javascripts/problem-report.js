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
  var TREE_URL = '../assets/problem-tree.json';
  var treeData = null;
  var treeStart = null;
  var treePath = [];   // [{ from, label, to }]，记录每步选择以支持面包屑回退
  var treeCurrent = null;

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

  function filterRepos() {
    var q = repoInput.value.trim().toLowerCase();
    var shown = 0;
    repoOptions.querySelectorAll('.pr-pill[data-repo]:not([data-other])').forEach(function (b) {
      var ok = !!q && b.getAttribute('data-repo').toLowerCase().indexOf(q) !== -1;
      b.classList.toggle('is-match', ok);
      if (ok) shown++;
    });
    var other = repoOptions.querySelector('.pr-pill[data-other]');
    if (other) other.classList.toggle('is-match', !!q && shown === 0);
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
    var q = labelSearch.value.trim().toLowerCase();
    var shown = 0;
    labelOptions.querySelectorAll('.pr-pill[data-label]:not([data-other])').forEach(function (b) {
      var ok = !!q && b.getAttribute('data-label').toLowerCase().indexOf(q) !== -1;
      b.classList.toggle('is-match', ok);
      if (ok) shown++;
    });
    var other = labelOptions.querySelector('.pr-pill[data-other]');
    if (other) other.classList.toggle('is-match', !!q && shown === 0);
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
    var body = [
      '### 概览', '', overview, '',
      '### runs-on 标签', '', '```\n' + state.label + '\n```', '',
      '### 问题 URL', '', urlText, '',
      '### 简单描述你看到的现象', '', descBullets(), '',
      '### 错误信息', '', '```bash\n' + (errInput.value.trim() || '无') + '\n```', ''
    ].join('\n');
    var task = descTask.value.trim();
    var title = '[缺陷]: 业务反馈 ' + state.repo + (task ? ' 的 ' + task : '') + ' 出现问题';
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
    treePath = [];
    treeCurrent = treeData && treeStart ? treeStart : null;
  }

  function treeRenderPath() {
    if (!treePathEl) return;
    treePathEl.innerHTML = treePath.map(function (c, i) {
      return '<button type="button" class="pr-tree-crumb" data-index="' + i + '">' +
        escapeHtml(c.label) + '</button>';
    }).join('<span class="pr-tree-arrow">→</span>');
  }

  function treeRenderNode() {
    if (!treeNodeEl || !treeData || !treeCurrent) return;
    var node = treeData.nodes[treeCurrent];
    if (!node) return;
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
      treeNodeEl.innerHTML =
        '<div class="pr-leaf">' +
          '<p class="pr-leaf-title">' + escapeHtml(node.title || '') + '</p>' +
          '<p class="pr-leaf-summary">' + escapeHtml(node.summary || '') + '</p>' +
          (steps ? '<ol class="pr-leaf-steps">' + steps + '</ol>' : '') +
          (links ? '<div class="pr-leaf-links">' + links + '</div>' : '') +
          '<div class="pr-leaf-actions">' +
            '<button type="button" class="pr-btn pr-btn-sm pr-leaf-solved">已解决，无需登记</button>' +
            '<button type="button" class="pr-btn pr-btn-sm" id="pr-leaf-continue">仍未解决 → 继续登记</button>' +
          '</div>' +
        '</div>';
    }
  }

  if (treeNodeEl) {
    treeNodeEl.addEventListener('click', function (e) {
      var branch = e.target.closest('.pr-tree-branch');
      if (branch) {
        treePath.push({
          from: treeCurrent,
          label: branch.getAttribute('data-label'),
          to: branch.getAttribute('data-to')
        });
        treeCurrent = branch.getAttribute('data-to');
        treeRenderNode();
        return;
      }
      if (e.target.closest('#pr-leaf-continue')) { setStep(2); return; }
      if (e.target.closest('.pr-leaf-solved')) { treeReset(); treeRenderNode(); }
    });
  }

  if (treePathEl) {
    treePathEl.addEventListener('click', function (e) {
      var crumb = e.target.closest('.pr-tree-crumb');
      if (!crumb) return;
      var idx = parseInt(crumb.getAttribute('data-index'), 10);
      if (isNaN(idx) || !treePath[idx]) return;
      treeCurrent = treePath[idx].from;
      treePath = treePath.slice(0, idx);
      treeRenderNode();
    });
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
        treeReset();
        treeRenderNode();
      })
      .catch(function () {
        treeNodeEl.innerHTML = '<p class="pr-hint">自助决策树加载失败，可直接点「下一步」继续登记。</p>';
      });
  }

  setStep(1);
})();
