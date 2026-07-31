/* Table sort with asc/desc cycle for MkDocs Material tables.
   The Repo.md table (marked by <!-- CACHE_AUDIT_TABLE_START -->) auto-sorts
   ascending on its first column (Repository) on load.
   Runs immediately + on DOMContentLoaded + via MutationObserver so it works
   regardless of when the table appears. */
(function () {
  var state = new WeakMap(); // table -> { col, dir }

  function cellText(td) {
    var s = td && (td.textContent != null ? td.textContent : td.innerText);
    return (s || "").toString().trim().toLowerCase();
  }

  function isNumeric(s) {
    return s !== "" && !isNaN(Number(s));
  }

  function compareValues(a, b, numeric) {
    if (numeric) return Number(a) - Number(b);
    return a < b ? -1 : a > b ? 1 : 0;
  }

  function applySort(table, colIdx, dir) {
    var tbody = table.querySelector("tbody");
    var ths = Array.from(table.querySelectorAll("thead th"));
    if (!tbody || colIdx >= ths.length) return;

    var rows = Array.from(tbody.querySelectorAll("tr"));
    var numeric = rows.every(function (r) {
      var td = r.querySelectorAll("td")[colIdx];
      return td && (isNumeric(cellText(td)) || cellText(td) === "-");
    });
    rows.sort(function (a, b) {
      var ta = cellText(a.querySelectorAll("td")[colIdx] || a);
      var tb = cellText(b.querySelectorAll("td")[colIdx] || b);
      if (ta === "-" && tb === "-") return 0;
      if (ta === "-") return 1;
      if (tb === "-") return -1;
      return compareValues(ta, tb, numeric) * (dir === "asc" ? 1 : -1);
    });
    rows.forEach(function (r) { tbody.appendChild(r); });

    ths.forEach(function (t) { t.dataset.sortDir = ""; });
    ths[colIdx].dataset.sortDir = dir;
  }

  function sortTable(th) {
    var table = th.closest("table");
    var ths = Array.from(table.querySelectorAll("thead th"));
    var colIdx = ths.indexOf(th);
    var s = state.get(table) || { col: -1, dir: "" };
    var dir = (s.col === colIdx && s.dir === "asc") ? "desc" : "asc";
    applySort(table, colIdx, dir);
    state.set(table, { col: colIdx, dir: dir });
  }

  function initTable(table) {
    if (state.has(table)) return; // already wired up
    var thead = table.querySelector("thead");
    var tbody = table.querySelector("tbody");
    if (!thead || !tbody) return;
    state.set(table, { col: -1, dir: "" });
    thead.querySelectorAll("th").forEach(function (th) {
      th.classList.add("sortable");
      th.title = "Click to sort (click again to reverse)";
      th.addEventListener("click", function () { sortTable(th); });
    });
  }

  /* Find tables preceded by a CACHE_AUDIT_TABLE_START marker (Repo.md) and
     sort column 0 ascending — unless the user has already sorted it. */
  function applyDefaultSorts() {
    document.querySelectorAll("article").forEach(function (article) {
      var walker = document.createTreeWalker(article, NodeFilter.SHOW_COMMENT);
      while (walker.nextNode()) {
        var comment = walker.currentNode;
        if (comment.nodeValue.indexOf("CACHE_AUDIT_TABLE_START") === -1) continue;
        var el = comment.nextSibling;
        while (el && el.nodeType !== Node.ELEMENT_NODE) el = el.nextSibling;
        if (!el || el.tagName !== "TABLE") continue;
        initTable(el);
        var s = state.get(el);
        if (s && s.col !== -1) continue; // already sorted by user
        applySort(el, 0, "asc");
        state.set(el, { col: 0, dir: "asc" });
      }
    });
  }

  function initAll() {
    document.querySelectorAll("article table").forEach(initTable);
    applyDefaultSorts();
  }

  document.addEventListener("DOMContentLoaded", initAll);
  initAll(); // covers case where DOM is already parsed
  var timer;
  var observer = new MutationObserver(function () {
    clearTimeout(timer);
    timer = setTimeout(initAll, 150);
  });
  observer.observe(document.body, { childList: true, subtree: true });
})();
