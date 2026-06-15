// Server-side render for the Refinery board. Two pages share one layout:
//   • Gauntlet (/)   — PROJECTS (triaged items) moving through PHASES, in lanes
//     by phase status, tinted by their profile's color. Parked projects carry
//     amend + rewind controls. A profiles legend (color swatch + pipeline) sits
//     alongside — it's a key, not a control (profiles are always available to
//     triage; the human gate is per-project, at a phase).
//   • Hopper (/hopper) — raw IDEAS not yet triaged, plus the intake box.
// Plain form-posts (POST → 303 → GET); no client framework.

import { Item } from "../contracts.js";
import { ResolvedProfile } from "../profiles/catalog.js";

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string),
  );
}

const NEUTRAL = "#a89984";
function colorOf(genre: string, profiles: ResolvedProfile[]): string {
  return profiles.find((p) => p.genre === genre)?.color ?? NEUTRAL;
}
function titleOf(item: Item): string {
  return item.payload && typeof item.payload === "object" && "title" in item.payload
    ? String((item.payload as { title: unknown }).title)
    : item.id;
}

// phaseStatus → friendly gauntlet lane (DataX-board-style).
const LANES: { status: Item["phaseStatus"]; label: string }[] = [
  { status: "pending", label: "In Progress" },
  { status: "parked", label: "Needs You" },
  { status: "passed", label: "Done" },
  { status: "failed", label: "Failed" },
];

const STYLE = `<style>
  :root{--bg:#1d2021;--panel:#282828;--ink:#ebdbb2;--dim:#a89984;--line:#3c3836;--acc:#fe8019}
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.4 ui-sans-serif,system-ui,sans-serif}
  header{padding:12px 18px;border-bottom:1px solid var(--line);display:flex;gap:16px;align-items:baseline}
  header h1{margin:0;font-size:17px}
  nav a{color:var(--dim);text-decoration:none;margin-right:14px;font-size:13px}
  nav a.active{color:var(--ink);border-bottom:2px solid var(--acc);padding-bottom:2px}
  button{background:var(--line);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:6px 10px;cursor:pointer}
  button:hover{border-color:var(--acc)}
  .intake{display:flex;gap:8px;padding:12px 18px;border-bottom:1px solid var(--line)}
  .intake input[type=text]{flex:1;background:var(--bg);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:8px}
  .wrap{display:flex;gap:12px;padding:14px;align-items:flex-start}
  .legend{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:240px;padding:10px}
  .legend h2{margin:0 0 8px;font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--dim)}
  .prow{display:flex;flex-direction:column;gap:2px;padding:6px 0;border-top:1px solid var(--line)}
  .pname{display:flex;align-items:center;gap:6px;font-size:13px}
  .swatch{width:10px;height:10px;border-radius:50%;display:inline-block}
  .pmeta{color:var(--dim);font-size:11px}
  .pipe{color:var(--dim);font-size:11px}
  .board{display:flex;gap:12px;flex:1;overflow-x:auto}
  .col{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:230px;flex:1}
  .col h2{margin:0;padding:10px 12px;font-size:13px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;text-transform:uppercase}
  .count{background:var(--line);border-radius:10px;padding:0 8px;color:var(--dim)}
  .cards{padding:8px;display:flex;flex-direction:column;gap:8px}
  .empty{color:var(--line);text-align:center;padding:8px}
  .card{background:var(--bg);border:1px solid var(--line);border-left:4px solid var(--dim);border-radius:6px;padding:8px 10px}
  .badges{display:flex;gap:6px;margin-bottom:4px;flex-wrap:wrap}
  .badge{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim)}
  .badge.profile{color:#1d2021;font-weight:600}
  .title{font-size:13px}.reason{margin-top:5px;font-size:12px;color:var(--acc)}
  .ctl{display:flex;gap:6px;margin-top:6px}
  .ctl input[type=text]{flex:1;background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:4px;padding:4px}
  .ctl select{background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:4px}
</style>`;

function layout(active: "gauntlet" | "hopper", body: string): string {
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Refinery</title>${STYLE}</head><body>
<header><h1>🛠 Refinery</h1><nav>
  <a href="/" class="${active === "gauntlet" ? "active" : ""}">Gauntlet</a>
  <a href="/hopper" class="${active === "hopper" ? "active" : ""}">Hopper</a>
  <a href="/cards">Nightly cards</a>
</nav></header>
${body}
</body></html>`;
}

function legend(profiles: ResolvedProfile[]): string {
  const rows = profiles
    .map(
      (p) => `<div class="prow">
        <span class="pname"><span class="swatch" style="background:${esc(p.color)}"></span>${esc(p.label)}</span>
        <span class="pmeta">${esc(p.genre)} · ${esc(p.llmProvider)} · ${p.executeMode}${p.enabled ? "" : " · (off)"}</span>
        <span class="pipe">${p.gates.map(esc).join(" → ")}</span>
      </div>`,
    )
    .join("");
  return `<section class="legend"><h2>Profiles (colors)</h2>${rows || '<div class="empty">none</div>'}</section>`;
}

function rewindTargets(item: Item, profiles: ResolvedProfile[]): string[] {
  const profile = profiles.find((p) => p.genre === item.genre);
  if (!profile) return [];
  const idx = profile.gates.indexOf(item.phase);
  return idx > 0 ? profile.gates.slice(0, idx) : profile.gates.filter((g) => g !== item.phase);
}

function projectCard(item: Item, profiles: ResolvedProfile[]): string {
  const color = colorOf(item.genre, profiles);
  const reason = item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : "";
  let controls = "";
  if (item.phaseStatus === "parked") {
    const targets = rewindTargets(item, profiles);
    const rewindForm = targets.length
      ? `<form method="post" action="/rewind" class="ctl">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <select name="toPhase">${targets.map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join("")}</select>
           <input type="text" name="note" placeholder="why rewind?" required>
           <button type="submit">⟲</button>
         </form>`
      : "";
    controls = `<form method="post" action="/amend" class="ctl">
        <input type="hidden" name="id" value="${esc(item.id)}">
        <input type="text" name="note" placeholder="answer / amendment" required>
        <button type="submit">✎</button>
      </form>${rewindForm}`;
  }
  return `<div class="card" style="border-left-color:${esc(color)}">
    <div class="badges"><span class="badge profile" style="background:${esc(color)}">${esc(item.genre)}</span><span class="badge">${esc(item.phase)}</span></div>
    <div class="title">${esc(titleOf(item))}</div>
    ${reason}${controls}
  </div>`;
}

/** Gauntlet page: triaged PROJECTS in phase-status lanes, colored by profile. */
export function renderGauntlet(projects: Item[], profiles: ResolvedProfile[]): string {
  const lanes = LANES.map((lane) => {
    const inLane = projects.filter((p) => p.phaseStatus === lane.status);
    const body = inLane.length ? inLane.map((p) => projectCard(p, profiles)).join("") : `<div class="empty">—</div>`;
    return `<section class="col"><h2>${lane.label} <span class="count">${inLane.length}</span></h2><div class="cards">${body}</div></section>`;
  }).join("");
  return layout(
    "gauntlet",
    `<div class="wrap">${legend(profiles)}<div class="board">${lanes}</div></div>`,
  );
}

/** Hopper page: raw untriaged IDEAS + the intake box. */
export function renderHopperPage(ideas: Item[], profiles: ResolvedProfile[]): string {
  const cards = ideas.length
    ? ideas
        .map(
          (i) => `<div class="card" style="border-left-color:${NEUTRAL}">
            <div class="badges"><span class="badge">idea</span></div>
            <div class="title">${esc(titleOf(i))}</div>
            ${i.parkedReason ? `<div class="reason">${esc(i.parkedReason)}</div>` : ""}
          </div>`,
        )
        .join("")
    : `<div class="empty">no ideas waiting — type one above</div>`;
  const body = `
<form class="intake" method="post" action="/intake">
  <input type="text" name="text" placeholder="Drop an idea into the hopper — triage routes it to a profile…" required autofocus>
  <button type="submit">→ hopper</button>
</form>
<div class="wrap">${legend(profiles)}
  <div class="board"><section class="col"><h2>Ideas <span class="count">${ideas.length}</span></h2><div class="cards">${cards}</div></section></div>
</div>`;
  return layout("hopper", body);
}
