// Server-side render for the interactive board (the HTTP shell's view). Engine
// Items grouped into lanes by stageStatus; parked items carry an amend form and
// a rewind control scoped to the earlier gates of their profile. A profiles
// panel lists each profile with an enable/disable toggle, and an intake box
// posts a sentence to /intake. Plain HTML form-posts (POST → 303 → GET) — no
// client framework needed for a steering surface; htmx can layer on later.

import { Item } from "../contracts.js";
import { ResolvedProfile } from "../profiles/catalog.js";

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string),
  );
}

const LANES: { status: Item["stageStatus"]; label: string }[] = [
  { status: "pending", label: "Pending" },
  { status: "parked", label: "Parked" },
  { status: "passed", label: "Passed" },
  { status: "failed", label: "Failed" },
];

/** Gates of the item's profile that come before its current stage — rewind targets. */
function rewindTargets(item: Item, profiles: ResolvedProfile[]): string[] {
  const profile = profiles.find((p) => p.genre === item.genre);
  if (!profile) return [];
  const idx = profile.gates.indexOf(item.stage);
  return idx > 0 ? profile.gates.slice(0, idx) : profile.gates.filter((g) => g !== item.stage);
}

function amendRewindControls(item: Item, profiles: ResolvedProfile[]): string {
  const targets = rewindTargets(item, profiles);
  const rewindForm = targets.length
    ? `<form method="post" action="/rewind" class="ctl">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <select name="toStage">${targets.map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join("")}</select>
         <input type="text" name="note" placeholder="why rewind?" required>
         <button type="submit">⟲ rewind</button>
       </form>`
    : "";
  return `<form method="post" action="/amend" class="ctl">
      <input type="hidden" name="id" value="${esc(item.id)}">
      <input type="text" name="note" placeholder="answer / amendment" required>
      <button type="submit">✎ amend</button>
    </form>${rewindForm}`;
}

function cardHtml(item: Item, profiles: ResolvedProfile[]): string {
  const reason = item.parkedReason
    ? `<div class="reason">${esc(item.parkedReason)}</div>`
    : "";
  const controls = item.stageStatus === "parked" ? amendRewindControls(item, profiles) : "";
  const title =
    item.payload && typeof item.payload === "object" && "title" in item.payload
      ? String((item.payload as { title: unknown }).title)
      : item.id;
  return `<div class="card ${item.stageStatus}">
    <div class="badges"><span class="badge genre">${esc(item.genre)}</span><span class="badge stage">${esc(item.stage)}</span></div>
    <div class="title">${esc(title)}</div>
    ${reason}${controls}
  </div>`;
}

function profilesPanel(profiles: ResolvedProfile[]): string {
  const rows = profiles
    .map(
      (p) => `<div class="prow">
        <span class="pname">${esc(p.label)} <span class="pmeta">${esc(p.genre)} · ${esc(p.llmProvider)}</span></span>
        <form method="post" action="/profiles/toggle">
          <input type="hidden" name="genre" value="${esc(p.genre)}">
          <input type="hidden" name="enabled" value="${p.enabled ? "false" : "true"}">
          <button type="submit" class="toggle ${p.enabled ? "on" : "off"}">${p.enabled ? "on" : "off"}</button>
        </form>
      </div>`,
    )
    .join("");
  return `<section class="panel">
    <h2>Profiles</h2>
    ${rows || '<div class="empty">no profiles</div>'}
  </section>`;
}

export function renderBoard(items: Item[], profiles: ResolvedProfile[]): string {
  const lanes = LANES.map((lane) => {
    const inLane = items.filter((i) => i.stageStatus === lane.status);
    const body = inLane.length
      ? inLane.map((i) => cardHtml(i, profiles)).join("")
      : `<div class="empty">—</div>`;
    return `<section class="col"><h2>${lane.label} <span class="count">${inLane.length}</span></h2><div class="cards">${body}</div></section>`;
  }).join("");

  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Refinery — engine board</title>
<style>
  :root{--bg:#1d2021;--panel:#282828;--ink:#ebdbb2;--dim:#a89984;--line:#3c3836;
    --pending:#83a598;--parked:#fabd2f;--passed:#b8bb26;--failed:#cc241d;--acc:#fe8019}
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.4 ui-sans-serif,system-ui,sans-serif}
  header{padding:14px 18px;border-bottom:1px solid var(--line)}
  header h1{margin:0;font-size:18px}
  .intake{display:flex;gap:8px;padding:12px 18px;border-bottom:1px solid var(--line)}
  .intake input[type=text]{flex:1;background:var(--bg);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:8px}
  button{background:var(--line);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:6px 10px;cursor:pointer}
  button:hover{border-color:var(--acc)}
  .wrap{display:flex;gap:12px;padding:14px;align-items:flex-start}
  .panel{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:240px;padding:10px}
  .panel h2{margin:0 0 8px;font-size:13px;text-transform:uppercase;letter-spacing:.04em}
  .prow{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:4px 0;border-top:1px solid var(--line)}
  .pname{font-size:13px}.pmeta{color:var(--dim);font-size:11px}
  .toggle.on{color:var(--passed)}.toggle.off{color:var(--dim)}
  .board{display:flex;gap:12px;flex:1;overflow-x:auto}
  .col{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:240px;flex:1}
  .col h2{margin:0;padding:10px 12px;font-size:13px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;text-transform:uppercase}
  .count{background:var(--line);border-radius:10px;padding:0 8px;color:var(--dim)}
  .cards{padding:8px;display:flex;flex-direction:column;gap:8px}
  .empty{color:var(--line);text-align:center;padding:8px}
  .card{background:var(--bg);border:1px solid var(--line);border-left:3px solid var(--dim);border-radius:6px;padding:8px 10px}
  .card.pending{border-left-color:var(--pending)}.card.parked{border-left-color:var(--parked)}
  .card.passed{border-left-color:var(--passed)}.card.failed{border-left-color:var(--failed)}
  .badges{display:flex;gap:6px;margin-bottom:4px}
  .badge{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim)}
  .badge.genre{color:var(--ink)}
  .title{font-size:13px}.reason{margin-top:5px;font-size:12px;color:var(--parked)}
  .ctl{display:flex;gap:6px;margin-top:6px}
  .ctl input[type=text]{flex:1;background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:4px;padding:4px}
  .ctl select{background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:4px}
</style>
</head><body>
<header><h1>🛠 Refinery — engine board <a href="/hopper" style="font-size:13px;color:var(--dim);margin-left:10px">gauntlet hopper →</a></h1></header>
<form class="intake" method="post" action="/intake">
  <input type="text" name="text" placeholder="Type an idea or request — it gets triaged into a profile…" required autofocus>
  <button type="submit">intake →</button>
</form>
<div class="wrap">
  ${profilesPanel(profiles)}
  <div class="board">${lanes}</div>
</div>
</body></html>`;
}
