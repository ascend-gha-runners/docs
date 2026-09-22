/* Cluster Map interactions:
   - click a project head to expand/collapse its machines
   - text search (clusters / projects / runner labels) + hardware (NPU model)
     dropdown; matched projects auto-expand, machines filtered by NPU model. */
(function () {
  function init() {
    var input = document.getElementById("cluster-filter");
    var npuSelect = document.getElementById("cluster-npu");
    var grid = document.getElementById("cluster-grid");
    var empty = document.getElementById("cluster-empty");
    if (!input || !npuSelect || !grid) return;

    var hint = document.querySelector(".cluster-hint");
    var totalText = hint ? hint.textContent : "";
    if (hint && !hint.getAttribute("data-total")) hint.setAttribute("data-total", totalText);

    // --- expand/collapse -------------------------------------------------
    function expand(row, open) {
      var head = row.querySelector(".project-head");
      var list = row.querySelector(".machine-list");
      if (!head || !list) return;
      head.setAttribute("aria-expanded", open ? "true" : "false");
      list.hidden = !open;
    }
    grid.querySelectorAll(".project-head").forEach(function (btn) {
      btn.addEventListener("click", function () {
        var row = btn.closest(".project-row");
        expand(row, btn.getAttribute("aria-expanded") !== "true");
      });
    });

    // --- filtering -------------------------------------------------------
    // 支持多关键词：按空白（空格/Tab）分隔，所有关键词都命中（AND）才显示。
    // 例如「sglang a3」筛出 sglang 相关且含 a3 标签的项目。
    function tokenize(q) {
      return q ? q.split(/\s+/).filter(Boolean) : [];
    }

    function matchesSearch(tokens, cardName, rowSearch) {
      if (!tokens.length) return true;
      var hay = (cardName + '\n' + rowSearch).toLowerCase();
      return tokens.every(function (t) { return hay.indexOf(t) !== -1; });
    }

    // 判断单个标签文本是否命中任意关键词（用于高亮）。一个标签只需命中部分关键词即标注，
    // 例如「a2b3 hk」里「hk」命中集群名、只有「a2b3」落在标签上，此时仍高亮含 a2b3 的标签。
    function labelMatches(tokens, label) {
      if (!tokens.length) return false;
      var hay = label.toLowerCase();
      return tokens.some(function (t) { return hay.indexOf(t) !== -1; });
    }

    function apply() {
      var q = input.value.trim().toLowerCase();
      var tokens = tokenize(q);
      var npu = npuSelect.value;
      var hasFilter = !!(tokens.length || npu);
      var totalCards = 0;
      var visible = 0;

      grid.querySelectorAll(".cluster-card").forEach(function (card) {
        var cardName = card.getAttribute("data-name");
        var cardShown = false;
        card.querySelectorAll(".project-row").forEach(function (row) {
          var searchOk = matchesSearch(tokens, cardName, row.getAttribute("data-search") || "");
          var anyMachine = false;
          row.querySelectorAll(".machine").forEach(function (m) {
            var mNpu = m.getAttribute("data-npu") || "";
            var npuOk = !npu || mNpu.split(/\s+/).indexOf(npu) !== -1;
            var show = npuOk && searchOk;
            m.hidden = !show;
            if (show) anyMachine = true;
            // 命中关键词的 runner 标签（如 linux-aarch64-*）：所在灰色圆角框换成蓝色边框
            var labelEl = m.querySelector(".machine-label");
            var labelText = labelEl ? labelEl.textContent : "";
            m.classList.toggle("is-match", labelMatches(tokens, labelText));
          });
          var rowShown = anyMachine;
          row.classList.toggle("is-hidden", !rowShown);
          if (rowShown) cardShown = true;
          // auto-expand matched projects while filtering; restore collapsed when cleared
          expand(row, hasFilter ? rowShown : false);
        });
        card.classList.toggle("is-hidden", !cardShown);
        if (cardShown) visible++;
        totalCards++;
      });

      if (empty) empty.hidden = visible > 0;
      if (hint) {
        hint.textContent = hasFilter
          ? visible + " of " + totalCards + " clusters"
          : totalText;
      }
    }

    input.addEventListener("input", apply);
    npuSelect.addEventListener("change", apply);
  }

  document.addEventListener("DOMContentLoaded", init);
})();
