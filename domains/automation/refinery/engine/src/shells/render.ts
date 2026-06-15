// Server-side render for the Refinery board. Pages share one layout:
//   • Gauntlet (/)        — PROJECTS in phase-status lanes, tinted by profile
//                           color; nightly projects wear a 🌙 dashed-ring skin.
//   • Hopper (/hopper)    — raw untriaged IDEAS + the intake box.
//   • Nightly (/nightly)  — projects flagged nightly, in priority order, with a
//                           "max per night" cap. The overnight queue.
//   • Detail (/project/:id) — click-through detail + edit: amend, rewind, toggle
//                           nightly, and (for an idea) promote to a project.
// Cards are click-through; all actions live on the detail page. Plain
// form-posts (POST → 303); no client framework.

import { Item } from "../contracts.js";
import { ResolvedProfile } from "../profiles/catalog.js";

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string),
  );
}

const NEUTRAL = "#a89984";
const UNTRIAGED = "untriaged";
function colorOf(genre: string, profiles: ResolvedProfile[]): string {
  return profiles.find((p) => p.genre === genre)?.color ?? NEUTRAL;
}
function titleOf(item: Item): string {
  return item.payload && typeof item.payload === "object" && "title" in item.payload
    ? String((item.payload as { title: unknown }).title)
    : item.id;
}

const LANES: { status: Item["phaseStatus"]; label: string }[] = [
  { status: "pending", label: "In Progress" },
  { status: "parked", label: "Needs You" },
  { status: "passed", label: "Done" },
  { status: "failed", label: "Failed" },
];

const STYLE = `<style>
  :root{--bg:#1d2021;--panel:#282828;--ink:#ebdbb2;--dim:#a89984;--line:#3c3836;--acc:#fe8019}
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.4 ui-sans-serif,system-ui,sans-serif}
  a{color:var(--ink);text-decoration:none}
  header{padding:12px 18px;border-bottom:1px solid var(--line);display:flex;gap:16px;align-items:baseline}
  header h1{margin:0;font-size:17px}
  nav a{color:var(--dim);margin-right:14px;font-size:13px}
  nav a.active{color:var(--ink);border-bottom:2px solid var(--acc);padding-bottom:2px}
  button{background:var(--line);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:6px 10px;cursor:pointer}
  button:hover{border-color:var(--acc)}
  input[type=text],input[type=number],select,textarea{background:var(--bg);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:8px}
  .intake{display:flex;gap:8px;padding:12px 18px;border-bottom:1px solid var(--line)}
  .intake input[type=text]{flex:1}
  .wrap{display:flex;gap:12px;padding:14px;align-items:flex-start}
  .legend{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:230px;padding:10px}
  .legend h2{margin:0 0 8px;font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--dim)}
  .prow{display:flex;flex-direction:column;gap:2px;padding:6px 0;border-top:1px solid var(--line)}
  .pname{display:flex;align-items:center;gap:6px;font-size:13px}
  .swatch{width:10px;height:10px;border-radius:50%;display:inline-block}
  .pmeta,.pipe{color:var(--dim);font-size:11px}
  .board{display:flex;gap:12px;flex:1;overflow-x:auto}
  .col{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:230px;flex:1}
  .col h2{margin:0;padding:10px 12px;font-size:13px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;text-transform:uppercase}
  .count{background:var(--line);border-radius:10px;padding:0 8px;color:var(--dim)}
  .cards{padding:8px;display:flex;flex-direction:column;gap:8px}
  .empty{color:var(--line);text-align:center;padding:8px}
  .card{display:block;background:var(--bg);border:1px solid var(--line);border-left:4px solid var(--dim);border-radius:6px;padding:8px 10px}
  .card:hover{border-color:var(--acc)}
  .card.nightly{border:1px dashed var(--acc);border-left:4px solid var(--dim)}
  .badges{display:flex;gap:6px;margin-bottom:4px;flex-wrap:wrap;align-items:center}
  .badge{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim)}
  .badge.profile{color:#1d2021;font-weight:600}
  .moon{font-size:12px}
  .title{font-size:13px}.reason{margin-top:5px;font-size:12px;color:var(--acc)}
  /* detail + nightly */
  .detail{max-width:760px;margin:18px auto;padding:0 18px}
  .detail h2{font-size:15px;border-bottom:1px solid var(--line);padding-bottom:6px;margin-top:22px}
  .kv{color:var(--dim);font-size:13px}
  pre{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:10px;overflow-x:auto;font-size:12px}
  .act{display:flex;gap:6px;margin:8px 0;align-items:center;flex-wrap:wrap}
  .act input[type=text]{flex:1;min-width:200px}
  .hist{font-size:12px;color:var(--dim)}
  .nrow{display:flex;align-items:center;gap:10px;padding:8px 18px;border-bottom:1px solid var(--line)}
  .nrow.tonight{background:rgba(254,128,25,.08)}
  .nrow .t{flex:1}
</style>`;

function layout(active: string, body: string): string {
  const tab = (href: string, label: string, key: string) =>
    `<a href="${href}" class="${active === key ? "active" : ""}">${label}</a>`;
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Refinery</title>${STYLE}</head><body>
<header><h1>🛠 Refinery</h1><nav>
  ${tab("/", "Gauntlet", "gauntlet")}${tab("/hopper", "Hopper", "hopper")}${tab("/nightly", "Nightly", "nightly")}
</nav></header>
${body}
</body></html>`;
}

function legend(profiles: ResolvedProfile[]): string {
  const rows = profiles
    .map(
      (p) => `<div class="prow">
        <span class="pname"><span class="swatch" style="background:${esc(p.color)}"></span>${esc(p.label)}</span>
        <span class="pmeta">${esc(p.genre)} · ${esc(p.llmProvider)} · ${esc(p.executeMode)}</span>
        <span class="pipe">${p.gates.map(esc).join(" → ")}</span>
      </div>`,
    )
    .join("");
  return `<section class="legend"><h2>Profiles (colors)</h2>${rows || '<div class="empty">none</div>'}</section>`;
}

function cardLink(item: Item, profiles: ResolvedProfile[]): string {
  const color = colorOf(item.genre, profiles);
  const isIdea = item.genre === UNTRIAGED;
  const moon = item.nightly ? `<span class="moon" title="nightly">🌙</span>` : "";
  const badge = isIdea
    ? `<span class="badge">idea</span>`
    : `<span class="badge profile" style="background:${esc(color)}">${esc(item.genre)}</span><span class="badge">${esc(item.phase)}</span>`;
  return `<a class="card${item.nightly ? " nightly" : ""}" href="/project/${esc(item.id)}" style="border-left-color:${esc(color)}">
    <div class="badges">${badge}${moon}</div>
    <div class="title">${esc(titleOf(item))}</div>
    ${item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : ""}
  </a>`;
}

/** Gauntlet: triaged PROJECTS in phase-status lanes, colored by profile. */
export function renderGauntlet(projects: Item[], profiles: ResolvedProfile[]): string {
  const lanes = LANES.map((lane) => {
    const inLane = projects.filter((p) => p.phaseStatus === lane.status);
    const body = inLane.length ? inLane.map((p) => cardLink(p, profiles)).join("") : `<div class="empty">—</div>`;
    return `<section class="col"><h2>${lane.label} <span class="count">${inLane.length}</span></h2><div class="cards">${body}</div></section>`;
  }).join("");
  return layout("gauntlet", `<div class="wrap">${legend(profiles)}<div class="board">${lanes}</div></div>`);
}

/** Hopper: raw untriaged IDEAS + the intake box. */
export function renderHopperPage(ideas: Item[], profiles: ResolvedProfile[]): string {
  const cards = ideas.length
    ? ideas.map((i) => cardLink(i, profiles)).join("")
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

/** Nightly: projects flagged nightly, in priority order, with a per-night cap. */
export function renderNightly(
  nightly: Item[],
  maxPerNight: number,
  profiles: ResolvedProfile[],
): string {
  // already sorted by caller (priority desc)
  const rows = nightly
    .map((item, i) => {
      const color = colorOf(item.genre, profiles);
      const tonight = i < maxPerNight ? " tonight" : "";
      return `<div class="nrow${tonight}">
        <span class="swatch" style="background:${esc(color)}"></span>
        <a class="t" href="/project/${esc(item.id)}">${esc(titleOf(item))} <span class="kv">· ${esc(item.genre)} · ${esc(item.phase)}</span></a>
        ${i < maxPerNight ? '<span class="badge">tonight</span>' : ""}
        <form method="post" action="/nightly/bump" style="display:inline"><input type="hidden" name="id" value="${esc(item.id)}"><input type="hidden" name="dir" value="up"><button type="submit">▲</button></form>
        <form method="post" action="/nightly/bump" style="display:inline"><input type="hidden" name="id" value="${esc(item.id)}"><input type="hidden" name="dir" value="down"><button type="submit">▼</button></form>
      </div>`;
    })
    .join("");
  const body = `
<form class="intake" method="post" action="/nightly/config">
  <label class="kv">Max projects per night:</label>
  <input type="number" name="maxPerNight" min="0" value="${maxPerNight}" style="width:90px">
  <button type="submit">save</button>
  <span class="kv">${nightly.length} flagged · top ${Math.min(maxPerNight, nightly.length)} run tonight</span>
</form>
${rows || '<div class="empty" style="padding:24px">no projects flagged nightly — open a project and toggle 🌙</div>'}`;
  return layout("nightly", body);
}

/** Detail + edit page for one item (project or idea). */
export function renderProjectDetail(
  item: Item,
  profiles: ResolvedProfile[],
  enabledProfiles: ResolvedProfile[],
): string {
  const isIdea = item.genre === UNTRIAGED;
  const color = colorOf(item.genre, profiles);
  const profile = profiles.find((p) => p.genre === item.genre);
  const targets = profile
    ? (() => {
        const idx = profile.gates.indexOf(item.phase);
        return idx > 0 ? profile.gates.slice(0, idx) : profile.gates.filter((g) => g !== item.phase);
      })()
    : [];

  const history = item.history.length
    ? item.history.map((h) => `<div class="hist">${esc(h.at)} · <b>${esc(h.phase)}</b> · ${esc(h.status)}${h.note ? ` — ${esc(h.note)}` : ""}</div>`).join("")
    : `<div class="hist">—</div>`;

  const promote = isIdea
    ? `<h2>Promote to a project</h2>
       <form class="act" method="post" action="/promote">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <select name="genre">${enabledProfiles.map((p) => `<option value="${esc(p.genre)}">${esc(p.label)}</option>`).join("")}</select>
         <button type="submit">promote →</button>
       </form>`
    : "";

  const parkedActions =
    item.phaseStatus === "parked"
      ? `<form class="act" method="post" action="/amend">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <input type="text" name="note" placeholder="answer / amendment (re-arms the phase)" required>
           <button type="submit">✎ amend</button>
         </form>
         ${targets.length ? `<form class="act" method="post" action="/rewind">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <select name="toPhase">${targets.map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join("")}</select>
           <input type="text" name="note" placeholder="why rewind?" required>
           <button type="submit">⟲ rewind</button>
         </form>` : ""}`
      : `<div class="kv">No human action needed at this phase (${esc(item.phaseStatus)}).</div>`;

  const payloadObj = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
  const readonly = payloadObj.readonly === true;
  const run = typeof payloadObj.run === "string" ? payloadObj.run : "";
  const pr = typeof payloadObj.pr === "string" ? payloadObj.pr : "";

  const actions = readonly
    ? `<h2>Mirror (read-only)</h2>
       <div class="kv">Managed by the nightly-builds overnight run — refinery shows it but doesn't edit it.${run ? ` · run: ${esc(run)}` : ""}${pr ? ` · ${esc(pr)}` : ""}</div>`
    : `${promote}
  <h2>Human-in-the-loop</h2>
  ${parkedActions}

  <h2>Schedule</h2>
  <form class="act" method="post" action="/nightly/toggle">
    <input type="hidden" name="id" value="${esc(item.id)}">
    <input type="hidden" name="nightly" value="${item.nightly ? "false" : "true"}">
    <button type="submit">${item.nightly ? "🌙 remove from nightly" : "🌙 run overnight"}</button>
    <span class="kv">${item.nightly ? "queued for the overnight gauntlet run" : "runs only when advanced manually / on a beat"}</span>
  </form>

  <h2>Danger</h2>
  <form class="act" method="post" action="/delete">
    <input type="hidden" name="id" value="${esc(item.id)}">
    <button type="submit" style="border-color:#cc241d;color:#fb4934">🗑 delete</button>
    <span class="kv">removes this ${isIdea ? "idea" : "project"} from the board</span>
  </form>`;

  const body = `<div class="detail">
  <a href="/" class="kv">← board</a>
  <h2><span class="swatch" style="background:${esc(color)}"></span> ${esc(titleOf(item))}</h2>
  <div class="kv">${isIdea ? "idea (untriaged)" : `project · ${esc(item.genre)}`} · phase <b>${esc(item.phase)}</b> · ${esc(item.phaseStatus)} ${item.nightly ? "· 🌙 nightly" : ""}</div>
  ${item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : ""}

  ${actions}

  <h2>Payload</h2>
  <pre>${esc(JSON.stringify(item.payload, null, 2))}</pre>

  <h2>History</h2>
  ${history}
</div>`;
  return layout("", body);
}
