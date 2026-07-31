/* Simple table sort for MkDocs Material tables */
(function () {
  function cellText(td) {
    return td.innerText.trim().toLowerCase();
  }

  function isNumeric(s) {
    return s !== "" && !isNaN(Number(s));
  }

  function compareValues(a, b, numeric) {
    if (numeric) return Number(a) - Number(b);
    return a < b ? -1 : a > b ? 1 : 0;
  }

  function sortTable(th) {
    const table = th.closest("table");
    const tbody = table.querySelector("tbody");
    if (!tbody) return;

    const ths = Array.from(th.closest("tr").querySelectorAll("th"));
    const colIdx = ths.indexOf(th);
    const asc = th.dataset.sortDir !== "asc";
    th.dataset.sortDir = asc ? "asc" : "desc";

    // reset sibling arrows
    ths.forEach((t) => { t.dataset.sortDir = ""; });
    th.dataset.sortDir = asc ? "asc" : "desc";

    const rows = Array.from(tbody.querySelectorAll("tr"));
    const numeric = rows.every((r) => {
      const td = r.querySelectorAll("td")[colIdx];
      return td && (isNumeric(cellText(td)) || cellText(td) === "-");
    });

    rows.sort((a, b) => {
      const ta = cellText(a.querySelectorAll("td")[colIdx] || a);
      const tb = cellText(b.querySelectorAll("td")[colIdx] || b);
      if (ta === "-" && tb === "-") return 0;
      if (ta === "-") return 1;
      if (tb === "-") return -1;
      return compareValues(ta, tb, numeric) * (asc ? 1 : -1);
    });

    rows.forEach((r) => tbody.appendChild(r));
  }

  function initTable(table) {
    const thead = table.querySelector("thead");
    if (!thead) return;
    thead.querySelectorAll("th").forEach((th) => {
      th.style.cursor = "pointer";
      th.title = "Click to sort";
      th.addEventListener("click", () => sortTable(th));
    });
  }

  function initAll() {
    document.querySelectorAll("article table").forEach(initTable);
  }

  /* MkDocs Material re-renders content on tab switch */
  document.addEventListener("DOMContentLoaded", initAll);
  const observer = new MutationObserver(initAll);
  observer.observe(document.body, { childList: true, subtree: true });
})();
