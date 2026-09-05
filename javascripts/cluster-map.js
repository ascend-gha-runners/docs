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
    function matchesSearch(q, cardName, rowSearch) {
      if (!q) return true;
      if (cardName.toLowerCase().indexOf(q) !== -1) return true;
      return rowSearch.toLowerCase().indexOf(q) !== -1;
    }

    function apply() {
      var q = input.value.trim().toLowerCase();
      var npu = npuSelect.value;
      var hasFilter = !!(q || npu);
      var totalCards = 0;
      var visible = 0;

      grid.querySelectorAll(".cluster-card").forEach(function (card) {
        var cardName = card.getAttribute("data-name");
        var cardShown = false;
        card.querySelectorAll(".project-row").forEach(function (row) {
          var searchOk = matchesSearch(q, cardName, row.getAttribute("data-search") || "");
          var anyMachine = false;
          row.querySelectorAll(".machine").forEach(function (m) {
            var mNpu = m.getAttribute("data-npu") || "";
            var npuOk = !npu || mNpu.split(/\s+/).indexOf(npu) !== -1;
            var show = npuOk && searchOk;
            m.hidden = !show;
            if (show) anyMachine = true;
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
