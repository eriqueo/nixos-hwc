// Board table/lane enhancer — ONE self-contained vanilla-JS mechanism (no
// external deps, no CDN) that upgrades any container marked with a data
// attribute:
//   <table data-enhance="table">  — sortable headers + text filter; rows
//     sharing data-group travel together (fleet diverged sub-rows + member
//     expansions move with their cohort row).
//   <div data-enhance="lanes">    — lane board: text filter over cards, lane
//     toggle buttons, per-lane date sort over [data-date] card wrappers.
//
// Server output is complete without JS (progressive enhancement): the script
// injects every control it needs, so a no-JS page shows the full table/board
// and no dead widgets.
//
// One producer: `boardEnhancer` below IS the shipped script — render.ts
// embeds `boardEnhancer.toString()` into the page. Its pure helpers are
// exposed via `boardEnhancer(true)` (returns hooks, touches no DOM) so tests
// exercise the exact functions the browser runs.

export interface EnhancerHooks {
  sortKeyFromText: (s: string) => number | null;
  compareKeys: (a: number | null, b: number | null, dir: 1 | -1) => number;
  sortGroups: <T>(groups: { key: number | null; text: string; rows: T[] }[], dir: 1 | -1) => { key: number | null; text: string; rows: T[] }[];
}

/* eslint-disable @typescript-eslint/no-explicit-any */
// The engine tsconfig is node-only (no DOM lib) on purpose — server code must
// not silently reach for browser globals. This module is the one deliberate
// exception (it ships to the browser via toString), so the DOM surface is
// declared loosely here instead of turning the DOM lib on engine-wide.
declare const document: any;
type El = any;
export function boardEnhancer(hooksOnly?: boolean): EnhancerHooks | void {
  // Leading number of a cell, numeric-aware for the board's shapes:
  // "88.8%" → 88.8 · "≤0.27M / ≤1.75M (n=3)" → 0.27 · "1.2 / 2.8" → 1.2 ·
  // "27 (22/5⑂)" → 27 · "—"/"" → null (sorts last in BOTH directions).
  function sortKeyFromText(s: string): number | null {
    const m = s.replace(/[≤,]/g, "").match(/-?\d+(\.\d+)?/);
    return m ? parseFloat(m[0]) : null;
  }

  function compareKeys(a: number | null, b: number | null, dir: 1 | -1): number {
    if (a === null && b === null) return 0;
    if (a === null) return 1; // empties last regardless of direction
    if (b === null) return -1;
    return (a - b) * dir;
  }

  // Sort row GROUPS (a cohort row + its sub-rows), never raw rows. Groups
  // with a numeric key sort numerically; when fewer than half the groups
  // parse numeric, fall back to locale text (empties still last).
  function sortGroups<T>(
    groups: { key: number | null; text: string; rows: T[] }[],
    dir: 1 | -1,
  ): { key: number | null; text: string; rows: T[] }[] {
    const numeric = groups.filter((g) => g.key !== null).length * 2 >= groups.length && groups.length > 0;
    return [...groups].sort((x, y) =>
      numeric
        ? compareKeys(x.key, y.key, dir)
        : (x.text === "" ? 1 : y.text === "" ? -1 : x.text.localeCompare(y.text) * dir),
    );
  }

  if (hooksOnly) return { sortKeyFromText, compareKeys, sortGroups };

  const esc = (s: string) => s.toLowerCase();

  function makeFilterInput(placeholder: string, apply: (q: string) => void): El {
    const input = document.createElement("input");
    input.className = "tfilter";
    input.type = "search";
    input.placeholder = placeholder;
    input.addEventListener("input", () => apply(esc(input.value)));
    return input;
  }

  // ── tables ────────────────────────────────────────────────────────────────
  document.querySelectorAll('table[data-enhance="table"]').forEach((tableEl: El) => {
    const table = tableEl;
    const headRow = table.querySelector("tr");
    if (!headRow) return;
    const headers = Array.from(headRow.querySelectorAll("th"));
    const dataRows = () => Array.from(table.querySelectorAll("tr")).slice(1);

    // Row groups: a row plus every following row sharing its data-group — the
    // travel unit for both sorting and filtering. Rows without data-group are
    // their own group (plain tables enhance row-by-row).
    function readGroups(): { root: El; rows: El[] }[] {
      const out: { root: El; rows: El[] }[] = [];
      for (const r of dataRows() as El[]) {
        const prev = out[out.length - 1];
        if (prev && r.dataset.group && r.dataset.group === prev.root.dataset.group) prev.rows.push(r);
        else out.push({ root: r, rows: [r] });
      }
      return out;
    }

    let sortCol = -1;
    let dir: 1 | -1 = 1;
    headers.forEach((th: El, i: number) => {
      th.style.cursor = "pointer";
      th.title = "click to sort";
      th.addEventListener("click", () => {
        dir = sortCol === i ? ((dir * -1) as 1 | -1) : 1;
        sortCol = i;
        // Arrow lives in its own span — never rewrite th content (fleet
        // headers carry two-line markup).
        headers.forEach((h: El, j: number) => {
          let arr = h.querySelector(".arr");
          if (!arr) {
            arr = document.createElement("span");
            arr.className = "arr";
            h.appendChild(arr);
          }
          arr.textContent = j === i ? (dir === 1 ? " ▲" : " ▼") : "";
        });
        const groups = readGroups().map((g) => {
          const cell = g.root.cells[i];
          const text = cell ? cell.textContent!.trim() : "";
          return { key: sortKeyFromText(text), text: esc(text), rows: g.rows };
        });
        for (const g of sortGroups(groups, dir)) for (const r of g.rows) table.tBodies[0]
          ? table.tBodies[0].appendChild(r)
          : table.appendChild(r);
      });
    });

    // Member-row collapse: server renders member rows EXPANDED (no-JS pages
    // stay complete); JS collapses them and the ▾/▸ toggles (main row + the
    // diverged sub-row both carry one) reveal them per group.
    const expanded = new Set<string>();
    let query = "";
    const applyVisibility = () => {
      for (const g of readGroups()) {
        // A match anywhere in the group (member rows included) keeps the
        // whole group visible.
        const hay = esc(g.rows.map((r: El) => r.textContent || "").join(" "));
        const groupShown = !query || hay.indexOf(query) !== -1;
        for (const r of g.rows) {
          const isMem = r.classList.contains("mem");
          r.style.display = groupShown && (!isMem || expanded.has(g.root.dataset.group || "")) ? "" : "none";
        }
      }
    };
    table.querySelectorAll(".mtoggle").forEach((tg: El) => {
      tg.addEventListener("click", () => {
        const gid = tg.dataset.group || "";
        if (expanded.has(gid)) expanded.delete(gid); else expanded.add(gid);
        table.querySelectorAll(`.mtoggle[data-group="${gid}"]`).forEach((x: El) => {
          x.textContent = expanded.has(gid) ? "▾" : "▸";
        });
        applyVisibility();
      });
      tg.textContent = "▸"; // JS present → start collapsed
    });
    applyVisibility();
    table.parentElement!.insertBefore(makeFilterInput("filter rows…", (q: string) => { query = q; applyVisibility(); }), table);
  });

  // ── lane boards (gauntlet run lists) ─────────────────────────────────────
  document.querySelectorAll('div[data-enhance="lanes"]').forEach((wrapEl: El) => {
    const wrap = wrapEl;
    const cols = Array.from(wrap.querySelectorAll("section.col")) as El[];
    if (!cols.length) return;
    const cards = (col: El) => Array.from(col.querySelectorAll(".cardw")) as El[];

    const bar = document.createElement("div");
    bar.className = "lanebar";

    let query = "";
    const laneOff = new Set<string>();
    const apply = () => {
      for (const col of cols) {
        const lane = col.querySelector("h2")?.childNodes[0]?.textContent?.trim() ?? "";
        col.style.display = laneOff.has(lane) ? "none" : "";
        for (const c of cards(col)) {
          c.style.display = !query || esc(c.textContent || "").indexOf(query) !== -1 ? "" : "none";
        }
      }
    };

    bar.appendChild(makeFilterInput("filter runs…", (q) => { query = q; apply(); }));
    for (const col of cols) {
      const lane = col.querySelector("h2")?.childNodes[0]?.textContent?.trim() ?? "";
      const b = document.createElement("button");
      b.type = "button";
      b.className = "laneb on";
      b.textContent = lane;
      b.addEventListener("click", () => {
        if (laneOff.has(lane)) laneOff.delete(lane); else laneOff.add(lane);
        b.className = laneOff.has(lane) ? "laneb" : "laneb on";
        apply();
      });
      bar.appendChild(b);
    }

    const sortBtn = document.createElement("button");
    sortBtn.type = "button";
    sortBtn.className = "laneb";
    let dateDir: 1 | -1 = -1; // newest first
    const applySort = () => {
      sortBtn.textContent = dateDir === -1 ? "date ▼" : "date ▲";
      for (const col of cols) {
        const parent = col.querySelector(".cards");
        if (!parent) continue;
        const sorted = cards(col).sort((a: El, b: El) => {
          const da = a.dataset.date || "";
          const db = b.dataset.date || "";
          if (!da && !db) return 0;
          if (!da) return 1; // dateless last both directions
          if (!db) return -1;
          return da < db ? -1 * dateDir : da > db ? dateDir : 0;
        });
        for (const c of sorted) parent.appendChild(c);
      }
    };
    sortBtn.addEventListener("click", () => { dateDir = (dateDir * -1) as 1 | -1; applySort(); });
    bar.appendChild(sortBtn);
    applySort();

    wrap.parentElement!.insertBefore(bar, wrap);
  });
}

/** The inline script tag render.ts embeds — the function above, verbatim. */
export const ENHANCER_SCRIPT = `<script>(${boardEnhancer.toString()})();</script>`;
