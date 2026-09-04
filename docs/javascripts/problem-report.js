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
  // 第 1 步为自查（可选），无需必填校验；2/3/4/5 逐步校验必填项
  function validate(step) {
    if (step === 2 && !state.repo) return '请先选择项目（第 2 步）';
    if (step === 3 && !state.label) return '请选择 runs-on 标签（第 3 步）';
    if (step === 4) {
      if (!urlInput.value.trim()) return '请填写问题 URL';
      if (!descProblem.value.trim()) return '请描述出现的问题（第 4 步）';
    }
    if (step === 5 && !reporterInput.value.trim()) return '请填写提单人（姓名 工号）';
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
      .map(function (p) { return '- ' + p[0] + '：' + p[1]; });
    return lines.length ? lines.join('\n') : '';
  }

  function renderSummary() {
    var rows = [
      ['项目', state.repo],
      ['runs-on 标签', state.label],
      ['对应集群', labelClustersText()],
      ['问题 URL', urlInput.value.trim()],
      ['现象描述', descBullets()],
      ['提单人', reporterInput.value.trim()],
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
    // 问题 URL：按换行 / 空格 / 中英文逗号 分隔，每个链接单独一个 ``` 代码块，方便复制
    var urls = urlInput.value.trim().split(/[\n\s,，]+/).filter(Boolean);
    var urlBlock = urls.map(function (u) { return '```\n' + u + '\n```'; }).join('\n');
    var body = [
      '### 问题社区/仓库', '', state.repo, '',
      '### runs-on 标签', '', '```\n' + state.label + '\n```', '',
      '### 对应集群', '', '```\n' + labelClustersText() + '\n```', '',
      '### 问题 URL', '', urlBlock, '',
      '### 简单描述你看到的现象', '', descBullets(), '',
      '### 提单人', '', '```\n' + reporterInput.value.trim() + '\n```', '',
      '### 是否正在运行', '', runningChk.checked ? '是' : '否', '',
      '### 紧急程度', '', urgencyText(), '',
      '### 错误信息', '', errInput.value.trim() || '无', '',
      '### 是否为已知问题', '', knownChk.checked ? '是' : '否'
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

  setStep(1);
})();
