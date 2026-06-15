// domains/automation/refinery/app/src/render.ts
//
// Server-side render of the hopper as a Kanban. Read-only; one self-contained
// HTML page with a meta-refresh (no client framework needed for a viewer —
// htmx/interactivity arrives with the amend/rewind slice).

import type { Card, Idea, StatusGroup } from "./parse.ts";

const COLUMNS: { key: StatusGroup; label: string }[] = [
  { key: "draft", label: "Draft" },
  { key: "blocked", label: "Blocked" },
  { key: "queued", label: "Queued" },
  { key: "running", label: "Running" },
  { key: "done", label: "Done" },
  { key: "failed", label: "Failed" },
];

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c] as string),
  );
}

function ideaLane(ideas: Idea[]): string {
  if (ideas.length === 0) return "";
  const items = ideas
    .map(
      (i) => `<div class="card idea ${i.section}">
        <div class="badges"><span class="badge goal">${esc(i.goalId)}</span><span class="badge sec">${i.section}</span></div>
        <div class="title">${esc(i.text)}</div>
      </div>`,
    )
    .join("");
  return `<section class="col col-idea">
    <h2>Ideas <span class="count">${ideas.length}</span></h2>
    <div class="cards">${items}</div>
  </section>`;
}

function cardHtml(c: Card): string {
  const gate = c.gate ? `<div class="gate">⛔ ${esc(c.gate)}</div>` : "";
  const links: string[] = [];
  if (c.run) links.push(`<span class="link">▶ ${esc(c.run)}</span>`);
  if (c.pr) links.push(`<span class="link">⎇ ${esc(c.pr)}</span>`);
  const linksHtml = links.length ? `<div class="links">${links.join("")}</div>` : "";
  const step = c.step ? `<span class="badge step">${esc(c.step)}</span>` : "";
  return `<div class="card ${c.group}">
    <div class="badges"><span class="badge goal">${esc(c.goalId)}</span>${step}</div>
    <div class="title">${esc(c.title)}</div>
    ${gate}${linksHtml}
  </div>`;
}

export function renderPage(cards: Card[], ideas: Idea[]): string {
  const cols = COLUMNS.map((col) => {
    const inCol = cards.filter((c) => c.group === col.key);
    const body = inCol.length
      ? inCol.map(cardHtml).join("")
      : `<div class="empty">—</div>`;
    return `<section class="col col-${col.key}">
      <h2>${col.label} <span class="count">${inCol.length}</span></h2>
      <div class="cards">${body}</div>
    </section>`;
  }).join("");

  const total = cards.length;
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="10">
<title>Refinery — gauntlet hopper</title>
<style>
  :root{ --bg:#1d2021; --panel:#282828; --ink:#ebdbb2; --dim:#a89984; --line:#3c3836;
    --draft:#83a598; --blocked:#fb4934; --queued:#fabd2f; --running:#fe8019;
    --done:#b8bb26; --failed:#cc241d; --idea:#d3869b; }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.4 ui-sans-serif,system-ui,sans-serif}
  header{padding:14px 18px;border-bottom:1px solid var(--line);display:flex;gap:14px;align-items:baseline}
  header h1{margin:0;font-size:18px}
  header .sub{color:var(--dim);font-size:12px}
  .board{display:flex;gap:12px;padding:14px;overflow-x:auto;align-items:flex-start}
  .col{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:220px;max-width:300px;flex:1 0 220px}
  .col h2{margin:0;padding:10px 12px;font-size:13px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;text-transform:uppercase;letter-spacing:.04em}
  .count{background:var(--line);border-radius:10px;padding:0 8px;font-size:12px;color:var(--dim)}
  .cards{padding:8px;display:flex;flex-direction:column;gap:8px}
  .empty{color:var(--line);text-align:center;padding:8px}
  .card{background:var(--bg);border:1px solid var(--line);border-left:3px solid var(--dim);border-radius:6px;padding:8px 10px}
  .card.draft{border-left-color:var(--draft)} .card.blocked{border-left-color:var(--blocked)}
  .card.queued{border-left-color:var(--queued)} .card.running{border-left-color:var(--running)}
  .card.done{border-left-color:var(--done)} .card.failed{border-left-color:var(--failed)}
  .card.idea{border-left-color:var(--idea)}
  .badges{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:4px}
  .badge{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim)}
  .badge.goal{color:var(--ink)}
  .title{font-size:13px}
  .gate{margin-top:5px;font-size:12px;color:var(--blocked)}
  .links{margin-top:5px;display:flex;flex-direction:column;gap:2px}
  .link{font-size:11px;color:var(--dim);word-break:break-all}
  .col-idea{border-color:var(--idea)}
</style>
</head><body>
<header>
  <h1>🛠 Refinery — gauntlet hopper</h1>
  <span class="sub">${total} card${total === 1 ? "" : "s"} · ${ideas.length} idea${ideas.length === 1 ? "" : "s"} · auto-refresh 10s</span>
</header>
<div class="board">
  ${ideaLane(ideas)}
  ${cols}
</div>
</body></html>`;
}
