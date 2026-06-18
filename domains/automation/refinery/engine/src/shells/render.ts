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
import { mdToHtml } from "./markdown.js";

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string),
  );
}

const NEUTRAL = "#a7aaad"; // HWC palette fg2 (dim) — fallback for unknown genres
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
  { status: "running", label: "Running" },
  { status: "parked", label: "Needs You" },
  { status: "passed", label: "Done" },
  { status: "failed", label: "Failed" },
];

const STYLE = `<style>
  /* HWC brand palette (domains/home/theme/palettes/hwc.nix) — gruvbox-anchored,
     blue-shifted, copper-orange accent. bg0..3 depth, fg0..3, semantic status. */
  :root{
    --bg:#1d2021;--panel:#282828;--elev:#2c3338;--line:#32373c;
    --ink:#ebdbb2;--fg:#d5c4a1;--dim:#a7aaad;--muted:#50626f;
    --acc:#d08770;--acc2:#5e81ac;--ok:#a3be8c;--warn:#cf995f;--err:#bf616a;
  }
  *{box-sizing:border-box} body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.4 ui-sans-serif,system-ui,sans-serif}
  a{color:var(--fg);text-decoration:none}
  header{padding:12px 18px;border-bottom:1px solid var(--line);display:flex;gap:16px;align-items:baseline}
  header h1{margin:0;font-size:17px;color:var(--ink)}
  nav a{color:var(--dim);margin-right:14px;font-size:13px}
  nav a.active{color:var(--ink);border-bottom:2px solid var(--acc);padding-bottom:2px}
  button{background:var(--elev);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:6px 10px;cursor:pointer}
  button:hover{border-color:var(--acc)}
  input[type=text],input[type=number],select,textarea{background:var(--bg);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:8px}
  input:focus,select:focus,textarea:focus{outline:none;border-color:var(--acc)}
  .intake{display:flex;gap:8px;padding:12px 18px;border-bottom:1px solid var(--line);align-items:center}
  .intake input[type=text]{flex:1}
  .wrap{display:flex;gap:12px;padding:14px;align-items:flex-start}
  .swatch{width:10px;height:10px;border-radius:50%;display:inline-block}
  .board{display:flex;gap:12px;flex:1;overflow-x:auto}
  .col{background:var(--panel);border:1px solid var(--line);border-radius:8px;min-width:230px;flex:1}
  .col h2{margin:0;padding:10px 12px;font-size:13px;border-bottom:1px solid var(--line);display:flex;justify-content:space-between;text-transform:uppercase;letter-spacing:.04em;color:var(--dim)}
  .count{background:var(--elev);border-radius:10px;padding:0 8px;color:var(--dim);font-weight:600}
  .cards{padding:8px;display:flex;flex-direction:column;gap:8px}
  /* Hopper: ideas have no status lane → a responsive card grid (SR2-style faces) */
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:12px;padding:14px}
  .empty{color:var(--muted);text-align:center;padding:8px}
  /* Card — SR2 face: type-tinted fill via color-mix, type-color left edge, hover ring */
  .card{display:block;background:var(--elev);border:1px solid var(--line);border-left:4px solid var(--dim);border-radius:8px;padding:9px 11px;transition:box-shadow .12s,border-color .12s}
  .card:hover{border-color:var(--acc);box-shadow:0 0 0 1px color-mix(in srgb,var(--acc) 45%,transparent)}
  .card.nightly{border:1px dashed var(--warn);border-left-width:4px}
  .badges{display:flex;gap:6px;margin-bottom:5px;flex-wrap:wrap;align-items:center}
  .badge{font-size:10px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim);border:1px solid transparent}
  .badge.type{font-weight:700;text-transform:uppercase;letter-spacing:.05em}
  .moon{font-size:12px}
  .title{display:block;font-size:13px;color:var(--ink);font-weight:600;overflow-wrap:anywhere}
  a.title:hover{color:var(--acc)}
  .reason{margin-top:5px;font-size:12px;color:var(--acc)}
  .card .why{margin-top:2px;font-size:12px;color:var(--dim);overflow-wrap:anywhere}
  /* inline per-card controls (SR2-style quick actions) */
  .ccrow{display:flex;gap:5px;margin-top:8px;flex-wrap:wrap;align-items:center}
  .cc{display:inline-flex;gap:4px;margin:0}
  .ccrow select,.cc select,.ccrow button,.cc button{font-size:11px;padding:3px 6px;border-radius:5px;line-height:1.1}
  .ccrow select,.cc select{max-width:130px}
  .ccrow .danger:hover,.cc .danger:hover{border-color:var(--err);color:var(--err)}
  /* detail + nightly */
  .detail{max-width:760px;margin:18px auto;padding:0 18px}
  .detail h2{font-size:15px;border-bottom:1px solid var(--line);padding-bottom:6px;margin-top:22px}
  .kv{color:var(--dim);font-size:13px}
  pre{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:10px;overflow-x:auto;font-size:12px}
  .act{display:flex;gap:6px;margin:8px 0;align-items:center;flex-wrap:wrap}
  .act input[type=text]{flex:1;min-width:200px}
  .hist{font-size:12px;color:var(--dim)}
  /* rendered markdown (reports, card bodies) — wraps, doesn't clip */
  .md{max-width:840px;line-height:1.55}
  .md h2,.md h3,.md h4,.md h5{margin:16px 0 6px;font-size:14px;color:var(--ink)}
  .md p{margin:8px 0;overflow-wrap:anywhere}
  .md ul,.md ol{margin:6px 0 6px 20px}
  .md li{margin:3px 0}
  .md code{background:var(--line);padding:1px 4px;border-radius:3px;font-size:12px}
  .md pre.code{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:10px;white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}
  .md blockquote{border-left:3px solid var(--line);margin:6px 0;padding-left:10px;color:var(--dim)}
  .md a{color:var(--acc2);overflow-wrap:anywhere}
  /* OKF vault cross-links: styled but non-navigable (board can't resolve vault paths yet) */
  .md .vlink{color:var(--acc2);border-bottom:1px dotted var(--acc2);cursor:help;overflow-wrap:anywhere}
  /* SR tabbed detail (mirrors the SR2/datax ticket-editor); the SR list is the shared kanban */
  .srtabs{max-width:860px;margin:0 auto;padding:0 18px}
  .srtabs > input{display:none}
  .srhead{padding:14px 0 4px}
  .srhead .cat{font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:var(--acc2);font-weight:700}
  .srhead h2{margin:2px 0;font-size:18px;border:0}
  .srhead .q{color:var(--dim);font-size:13px}
  .srtabbar{display:flex;gap:4px;border-bottom:1px solid var(--line);margin-top:10px}
  .srtabs label{padding:8px 14px;cursor:pointer;color:var(--dim);border-bottom:2px solid transparent;font-size:13px}
  .srtabs .panel{display:none;padding:14px 0}
  #srt-gameplan:checked ~ .srtabbar label[for=srt-gameplan],
  #srt-thread:checked ~ .srtabbar label[for=srt-thread],
  #srt-details:checked ~ .srtabbar label[for=srt-details]{color:var(--ink);border-bottom-color:var(--acc)}
  #srt-gameplan:checked ~ #srp-gameplan,
  #srt-thread:checked ~ #srp-thread,
  #srt-details:checked ~ #srp-details{display:block}
  /* project step progress */
  .bar{height:6px;background:var(--line);border-radius:3px;overflow:hidden;margin-top:6px}
  .bar > span{display:block;height:100%;background:var(--done,var(--ok))}
  .steps{margin-top:8px}
  .step{display:flex;gap:8px;align-items:center;padding:6px 0;border-top:1px solid var(--line);font-size:13px}
  .step .n{color:var(--dim);width:22px;flex:none}
  .step .ti{flex:1;overflow-wrap:anywhere}
  .step .st{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim)}
  .step .st.done{color:var(--bg);background:var(--ok)}
  .step .st.queued,.step .st.running{color:var(--bg);background:var(--acc)}
</style>`;

function layout(active: string, body: string): string {
  const tab = (href: string, label: string, key: string) =>
    `<a href="${href}" class="${active === key ? "active" : ""}">${label}</a>`;
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Refinery</title>${STYLE}</head><body>
<header><h1>🛠 Refinery</h1><nav>
  ${tab("/", "Gauntlet", "gauntlet")}${tab("/hopper", "Hopper", "hopper")}${tab("/nightly", "Nightly", "nightly")}${tab("/sr", "SR", "sr")}
</nav></header>
${body}
</body></html>`;
}

// ONE card renderer for every surface (Card Standard v0.1: compact face →
// detail). Face anatomy: identity (the /project/:id URL that round-trips it),
// kind/type → profile color (categorical, never decoration), title (who/what),
// why-it-matters (one-line summary), status/signal badges, and ≥1 action (the
// card itself is the click-through; all controls live on the detail page).
const STATUS_LANES = LANES.map((l) => ({ key: l.status as string, label: l.label }));
const statusOf = (item: Item): string => item.phaseStatus;
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === "object" ? (v as Record<string, unknown>) : {});

// Each board POST carries `back` so the handler redirects to the board the user
// is on (not the detail page) — they see the card change lane in place.
function backField(back: string): string {
  return `<input type="hidden" name="back" value="${esc(back)}">`;
}

// Inline per-card controls (SR2 ticket-card quick actions, no-framework form
// posts). Kind decides the controls: ideas promote; engine projects get a status
// dropdown + run + nightly + delete; read-only nightly mirror cards get the
// vault-backed queue/run/mode; other read-only cards (SR) get none.
function controlsFor(item: Item, enabled: ResolvedProfile[], back: string): string {
  const pl = obj(item.payload);
  const isIdea = item.genre === UNTRIAGED;
  const readonly = pl.readonly === true;
  const idIn = `<input type="hidden" name="id" value="${esc(item.id)}">`;
  const bk = backField(back);

  if (readonly) {
    // read-only nightly-build mirror: vault-backed queue / run-now / mode toggle.
    const source = typeof pl.source === "string" ? pl.source : "";
    if (!source.startsWith("nightly")) return ""; // SR investigations: no inline controls
    const queued = typeof pl.queuedCount === "number" ? pl.queuedCount : 0;
    const done = typeof pl.stepsDone === "number" ? pl.stepsDone : 0;
    const total = typeof pl.stepsTotal === "number" ? pl.stepsTotal : 0;
    const allDone = total > 0 && done === total;
    const nextStatus = typeof pl.nextStatus === "string" ? pl.nextStatus : "";
    const nextBlocked = pl.nextBlocked === true;
    const mode = pl.mode === "immediate" ? "immediate" : "nightly";
    const queueBtn = queued > 0
      ? `<button type="submit" formaction="/card/queue" name="to" value="draft" title="unqueue">↩ unqueue</button>`
      : nextStatus
        ? `<button type="submit" formaction="/card/queue" name="to" value="queued" title="${nextBlocked ? "force-queue blocked step" : "queue next step"}">${nextBlocked ? "⚠ force-queue" : "✅ queue"}</button>`
        : "";
    const runBtn = allDone ? "" : `<button type="submit" formaction="/card/run-now" title="run this project now">▶ now</button>`;
    const modeBtn = `<button type="submit" formaction="/card/mode" name="mode" value="${mode === "immediate" ? "nightly" : "immediate"}" title="now ${mode}; switch">${mode === "immediate" ? "⚡" : "🌙"}</button>`;
    return `<form class="ccrow" method="post" action="/card/queue">${idIn}${bk}${queueBtn}${runBtn}${modeBtn}</form>`;
  }

  if (isIdea) {
    const opts = enabled.map((p) => `<option value="${esc(p.genre)}">${esc(p.label)}</option>`).join("");
    return `<div class="ccrow">
      <form class="cc" method="post" action="/promote">${idIn}${bk}
        <select name="genre" title="promote to a profile">${opts}</select>
        <button type="submit">promote →</button>
      </form>
      <form class="cc" method="post" action="/delete">${idIn}${bk}<button type="submit" class="danger" title="delete idea">🗑</button></form>
    </div>`;
  }

  // engine project: change lane (status dropdown), run, nightly toggle, delete.
  const statusOpts = STATUS_LANES.map(
    (l) => `<option value="${l.key}"${item.phaseStatus === l.key ? " selected" : ""}>${esc(l.label)}</option>`,
  ).join("");
  const statusSel = `<form class="cc" method="post" action="/status">${idIn}${bk}<select name="status" title="move to lane" onchange="this.form.submit()">${statusOpts}</select></form>`;
  const runBtn = item.phaseStatus === "running"
    ? `<span class="badge">running…</span>`
    : `<form class="cc" method="post" action="/run">${idIn}${bk}<button type="submit" title="run the pipeline now">▶</button></form>`;
  const nightlyBtn = `<form class="cc" method="post" action="/nightly/toggle">${idIn}${bk}<input type="hidden" name="nightly" value="${item.nightly ? "false" : "true"}"><button type="submit" title="${item.nightly ? "remove from nightly" : "run overnight"}">${item.nightly ? "🌙✓" : "🌙"}</button></form>`;
  const delBtn = `<form class="cc" method="post" action="/delete">${idIn}${bk}<button type="submit" class="danger" title="delete project">🗑</button></form>`;
  return `<div class="ccrow">${statusSel}${runBtn}${nightlyBtn}${delBtn}</div>`;
}

function cardLink(item: Item, profiles: ResolvedProfile[], enabled: ResolvedProfile[] = [], back = "/"): string {
  const color = colorOf(item.genre, profiles);
  const isIdea = item.genre === UNTRIAGED;
  const pl = obj(item.payload);
  const moon = item.nightly ? `<span class="moon" title="nightly">🌙</span>` : "";
  const goal = typeof pl.goal === "string" ? pl.goal : "";
  const customer = typeof pl.customer === "string" ? pl.customer : "";
  const question = typeof pl.title === "string" ? pl.title : "";
  const hasReport = pl.hasReport === true;
  const total = typeof pl.stepsTotal === "number" ? pl.stepsTotal : 0;
  const doneN = typeof pl.stepsDone === "number" ? pl.stepsDone : 0;

  // Kind/type badge carries the categorical color (SR2 ticket-card style: type
  // color text on a faint color-mix fill + tinted border). Goal/phase/report are
  // neutral signal badges. Lane (column) encodes phase/status — color stays type.
  const c = esc(color);
  const typeBadge = isIdea
    ? `<span class="badge type">idea</span>`
    : `<span class="badge type" style="color:${c};background:color-mix(in srgb,${c} 18%,transparent);border-color:color-mix(in srgb,${c} 40%,transparent)">${esc(item.genre)}</span>`;
  const goalBadge = goal ? `<span class="badge">${esc(goal)}</span>` : "";
  const phaseBadge = isIdea ? "" : `<span class="badge">${esc(item.phase)}</span>`;
  const reportBadge = hasReport ? `<span class="badge" title="has REPORT">📄</span>` : "";

  const bar = total > 0
    ? `<div class="bar"><span style="width:${Math.round((doneN / total) * 100)}%"></span></div><div class="kv" style="font-size:11px;margin-top:3px">${doneN}/${total} steps done</div>`
    : "";

  // Title = who/what; for an SR the customer is the "who" and the question the
  // "why it matters". Otherwise the payload title (or id) is the title.
  const title = customer || titleOf(item);
  const why = customer && question ? `<div class="why">${esc(question)}</div>` : "";

  // SR2 ticket-card edge: type-color left border + faint type-tinted fill (ideas
  // stay neutral). color-mix over --elev so the tint reads on the dark surface.
  const skin = isIdea
    ? `border-left-color:var(--dim)`
    : `border-left-color:${c};background:color-mix(in srgb,${c} 12%,var(--elev))`;

  // Card is a container (not a link) so it can hold interactive controls; the
  // title is the click-through to the detail page.
  return `<div class="card${item.nightly ? " nightly" : ""}" style="${skin}">
    <div class="badges">${typeBadge}${goalBadge}${phaseBadge}${reportBadge}${moon}</div>
    <a class="title" href="/project/${esc(item.id)}">${esc(title)}</a>
    ${why}
    ${bar}
    ${item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : ""}
    ${controlsFor(item, enabled, back)}
  </div>`;
}

// Shared status-lane board: cards grouped into columns. Lane (column) = the
// phase/status axis; card color = the type axis. Used by every board page.
function laneBoard(
  projects: Item[],
  profiles: ResolvedProfile[],
  enabled: ResolvedProfile[],
  back: string,
  lanes: { key: string; label: string }[],
  keyOf: (item: Item) => string,
): string {
  const cols = lanes
    .map((lane) => {
      const inLane = projects.filter((p) => keyOf(p) === lane.key);
      const body = inLane.length ? inLane.map((p) => cardLink(p, profiles, enabled, back)).join("") : `<div class="empty">—</div>`;
      return `<section class="col"><h2>${esc(lane.label)} <span class="count">${inLane.length}</span></h2><div class="cards">${body}</div></section>`;
    })
    .join("");
  return `<div class="board">${cols}</div>`;
}

/** Gauntlet: triaged PROJECTS in phase-status lanes, colored by profile. */
export function renderGauntlet(projects: Item[], profiles: ResolvedProfile[], enabled: ResolvedProfile[] = []): string {
  return layout("gauntlet", `<div class="wrap">${laneBoard(projects, profiles, enabled, "/", STATUS_LANES, statusOf)}</div>`);
}

/** Hopper: raw untriaged IDEAS + the intake box. Ideas have no status lane, so
 *  they render as a responsive card grid (SR2 ticket-card faces) rather than a
 *  single full-width column. Each card promotes/deletes inline. */
export function renderHopperPage(ideas: Item[], profiles: ResolvedProfile[], enabled: ResolvedProfile[] = []): string {
  const cards = ideas.length
    ? `<div class="grid">${ideas.map((i) => cardLink(i, profiles, enabled, "/hopper")).join("")}</div>`
    : `<div class="empty" style="padding:24px">no ideas waiting — type one above</div>`;
  const body = `
<form class="intake" method="post" action="/intake">
  <input type="text" name="text" placeholder="Capture an idea — it lands here (and in the brain backlog); promote it to a project when ready…" required autofocus>
  <button type="submit">→ hopper</button>
</form>
<div class="col" style="margin:14px;border:0;background:transparent">
  <h2 style="border:0;padding:0 4px 8px">Ideas <span class="count">${ideas.length}</span></h2>
  ${cards}
</div>`;
  return layout("hopper", body);
}

/** Nightly: projects flagged nightly, as a status-lane kanban with a per-night
 *  cap. Each card carries its queue/run/mode controls inline. */
export function renderNightly(
  nightly: Item[],
  maxPerNight: number,
  profiles: ResolvedProfile[],
  enabled: ResolvedProfile[] = [],
): string {
  const queuedProjects = nightly.filter((i) => ((i.payload as { queuedCount?: number })?.queuedCount ?? 0) > 0).length;
  const board = laneBoard(nightly, profiles, enabled, "/nightly", STATUS_LANES, statusOf);
  const body = `
<form class="intake" method="post" action="/nightly/config">
  <label class="kv">Max cards per night:</label>
  <input type="number" name="maxPerNight" min="0" value="${maxPerNight}" style="width:90px">
  <button type="submit">save</button>
  <span class="kv">${nightly.length} projects · ${queuedProjects} with a step queued · run.sh runs up to ${maxPerNight} queued cards @ 01:30</span>
</form>
<div class="wrap">${nightly.length ? board : '<div class="empty" style="padding:24px">no nightly-build projects</div>'}</div>`;
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
  const goal = typeof payloadObj.goal === "string" ? payloadObj.goal : "";
  const cardBody = typeof payloadObj.body === "string" ? payloadObj.body : "";
  const input = typeof payloadObj.input === "string" ? payloadObj.input : "";

  const source = typeof payloadObj.source === "string" ? payloadObj.source : "";
  const isNightlyCard = source === "nightly-builds vault card";
  const cardStatus = typeof payloadObj.status === "string" ? payloadObj.status : "";
  const reportLink = (run || payloadObj.hasReport)
    ? `<a href="/report/${esc(item.id)}">📄 view REPORT</a>`
    : `<span class="kv">no REPORT yet</span>`;

  // Run button — triggers the engine pipeline (gates → effector) for a triaged
  // engine item. Read-only mirror items (nightly/SR cards) execute via their own
  // gauntlets, so they don't get it.
  const runBlock = (!isIdea && profile && !readonly)
    ? item.phaseStatus === "running"
      ? `<h2>Run</h2><div class="kv">⏳ running the ${esc(item.genre)} pipeline (${esc(profile.gates.join(" → "))})… refresh to see the result.</div>`
      : `<h2>Run</h2>
         <form class="act" method="post" action="/run">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <button type="submit">▶ run pipeline now</button>
           <span class="kv">runs ${esc(profile.gates.join(" → "))}; writes a developed spec</span>
         </form>`
    : "";

  const actions = readonly
    ? isNightlyCard
      ? // nightly-builds vault card: the Phase-4 queue gate as a button (writes
        // only the status field); run.sh @ 01:30 executes. + REPORT link.
        `<h2>Overnight queue</h2>
         <form class="act" method="post" action="/card/queue">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <input type="hidden" name="to" value="${cardStatus.startsWith("queued") ? "draft" : "queued"}">
           <button type="submit">${cardStatus.startsWith("queued") ? "↩ unqueue (draft)" : "✅ queue for tonight"}</button>
           <span class="kv">status: ${esc(cardStatus)} — run.sh @ 01:30 runs queued cards (NB_MAX_CARDS)</span>
         </form>
         <div class="act">${reportLink}${pr ? ` <span class="kv">· ${esc(pr)}</span>` : ""}</div>`
      : // sr_gauntlet investigation: pure read-only + REPORT.
        `<h2>Investigation (read-only)</h2>
         <div class="kv">Produced by the sr_gauntlet overnight run.</div>
         <div class="act">${reportLink}</div>`
    : `${promote}${runBlock}
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
    <button type="submit" style="border-color:var(--err);color:var(--err)">🗑 delete</button>
    <span class="kv">removes this ${isIdea ? "idea" : "project"} from the board</span>
  </form>`;

  const body = `<div class="detail">
  <a href="/" class="kv">← board</a>
  <h2><span class="swatch" style="background:${esc(color)}"></span> ${esc(titleOf(item))}</h2>
  <div class="kv">${isIdea ? "idea (untriaged)" : `project · ${esc(item.genre)}`}${goal ? ` · goal: <b>${esc(goal)}</b>` : ""} · phase <b>${esc(item.phase)}</b> · ${esc(item.phaseStatus)} ${item.nightly ? "· 🌙 nightly" : ""}</div>
  ${item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : ""}
  ${input ? `<div class="md"><p><em>${esc(input)}</em></p></div>` : ""}

  ${actions}

  ${cardBody ? `<h2>Card</h2><div class="md">${mdToHtml(cardBody)}</div>` : ""}

  <h2>Payload</h2>
  <pre>${esc(JSON.stringify(item.payload, null, 2))}</pre>

  <h2>History</h2>
  ${history}
</div>`;
  return layout("", body);
}

/** SR page: investigations as a status-lane kanban (cards = customer + question
 *  → tabbed detail). Lanes are the distinct SR statuses (data-driven), so a new
 *  status needs no renderer edit. */
export function renderSr(srs: Item[], maxPerNight: number, profiles: ResolvedProfile[]): string {
  const srStatusOf = (item: Item): string => {
    const p = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
    return typeof p.srStatus === "string" && p.srStatus ? p.srStatus : "investigated";
  };
  const lanes = [...new Set(srs.map(srStatusOf))].sort().map((s) => ({ key: s, label: s }));
  // SR cards are read-only mirrors (no inline controls); run-now lives on detail.
  const board = laneBoard(srs, profiles, [], "/sr", lanes, srStatusOf);
  const body = `
<form class="intake" method="post" action="/sr/config">
  <label class="kv">Max SRs per run:</label>
  <input type="number" name="maxPerNight" min="0" value="${maxPerNight}" style="width:90px">
  <button type="submit">save</button>
  <span class="kv">${srs.length} investigations · sr_gauntlet runs @ 06:30 (this cap)</span>
</form>
<div class="wrap">${srs.length ? board : '<div class="empty" style="padding:24px">no SR investigations yet — the gauntlet writes them under sr_gauntlet/investigations/</div>'}</div>`;
  return layout("sr", body);
}

export interface SrFiles {
  gameplan: string | null; // REPORT.md (the solution)
  thread: string | null; // sr.md (the conversation)
  context: string | null; // context.md (customer pack)
}

/** SR detail: the SR2 modal layout — header (category / customer / question) +
 *  Gameplan / Thread / Details tabs (CSS-only). The solution (REPORT) is the
 *  default tab so it's the thing you land on. */
export function renderSrDetail(item: Item, files: SrFiles): string {
  const p = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
  const customer = typeof p.customer === "string" && p.customer ? p.customer : (typeof p.srId === "string" ? p.srId : item.id);
  const question = typeof p.title === "string" ? p.title : "";
  const cat = typeof p.srStatus === "string" && p.srStatus ? p.srStatus : "investigated";
  const email = typeof p.email === "string" ? p.email : "";
  const phase = typeof p.srPhase === "string" ? p.srPhase : "";
  const srId = typeof p.srId === "string" ? p.srId : "";

  // Force a fresh investigation of this SR now (sr-gauntlet-runnow drains the
  // spool → run.sh --id). The board only writes the request.
  const runNow = srId
    ? `<form method="post" action="/sr/run-now" style="margin-top:8px">
         <input type="hidden" name="srId" value="${esc(srId)}">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <button type="submit" title="run the SR gauntlet on ${esc(srId)} now">▶ re-investigate now</button>
         <span class="kv">forces a fresh investigation; the report updates when it finishes</span>
       </form>`
    : "";

  const detailsMd = [
    `**Customer:** ${customer}`,
    email ? `**Email:** ${email}` : "",
    `**Status:** ${cat}${phase ? ` · phase ${phase}` : ""}`,
    typeof p.run === "string" ? `**Run:** ${p.run}` : "",
    "",
    files.context ? `## Customer context\n\n${files.context}` : "_no context.md_",
  ].filter(Boolean).join("\n");

  const panel = (md: string | null, empty: string) =>
    `<div class="md">${md ? mdToHtml(md) : `<p class="kv">${empty}</p>`}</div>`;

  const body = `<div class="srtabs">
  <input type="radio" name="srt" id="srt-gameplan" checked>
  <input type="radio" name="srt" id="srt-thread">
  <input type="radio" name="srt" id="srt-details">
  <div class="srhead">
    <a href="/sr" class="kv">← SR</a>
    <div class="cat">${esc(cat)}</div>
    <h2>${esc(customer)}</h2>
    <div class="q">${esc(question)}</div>
    ${runNow}
  </div>
  <div class="srtabbar">
    <label for="srt-gameplan">Gameplan</label>
    <label for="srt-thread">Thread</label>
    <label for="srt-details">Details</label>
  </div>
  <div class="panel" id="srp-gameplan">${panel(files.gameplan, "no REPORT.md for this investigation yet")}</div>
  <div class="panel" id="srp-thread">${panel(files.thread, "no thread (sr.md) captured")}</div>
  <div class="panel" id="srp-details">${panel(detailsMd, "")}</div>
</div>`;
  return layout("sr", body);
}

interface NbStepView {
  n: string; file: string; title: string; status: string; step: string; run: string; pr: string;
}
function stepClass(status: string): string {
  const s = status.toLowerCase();
  if (s.startsWith("done")) return "done";
  if (s.startsWith("queued") || s.startsWith("running")) return "queued";
  return "";
}

/** Nightly-builds PROJECT detail: goal + step progress + per-step status/report. */
export function renderNightlyProject(item: Item): string {
  const p = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
  const color = "#cf995f"; // HWC palette: warning (copper) — nightly-build tint
  const steps = Array.isArray(p.steps) ? (p.steps as NbStepView[]) : [];
  const done = typeof p.stepsDone === "number" ? p.stepsDone : 0;
  const total = typeof p.stepsTotal === "number" ? p.stepsTotal : steps.length;
  const queuedCount = typeof p.queuedCount === "number" ? p.queuedCount : 0;
  const goalId = typeof p.goal === "string" ? p.goal : "";
  const goalBody = typeof p.goalBody === "string" ? p.goalBody : "";
  const pct = total > 0 ? Math.round((done / total) * 100) : 0;

  const stepRows = steps
    .map((s) => {
      const reportLink = s.run ? `<a class="kv" href="/report/${encodeURIComponent("nbrun:" + s.run)}" title="REPORT">📄</a>` : "";
      return `<div class="step">
        <span class="n">${esc(s.n)}</span>
        <span class="ti">${esc(s.title)}${s.step ? ` <span class="kv">(${esc(s.step)})</span>` : ""}</span>
        ${reportLink}
        <span class="st ${stepClass(s.status)}">${esc(s.status)}</span>
      </div>`;
    })
    .join("");

  const allDone = total > 0 && done === total;
  const mode = p.mode === "immediate" ? "immediate" : "nightly";
  const nextStatus = typeof p.nextStatus === "string" ? p.nextStatus : "";
  const nextBlocked = p.nextBlocked === true;
  const idIn = `<input type="hidden" name="id" value="${esc(item.id)}">`;

  // The queue control is ALWAYS actionable for an unfinished project, so a
  // blocked-only project (the old purgatory case) is never a dead end:
  //   • a step queued → unqueue   • next is draft → queue next
  //   • next is blocked → force-queue (override)   • all done → just say so
  const queueControl =
    queuedCount > 0
      ? `<form class="act" method="post" action="/card/queue">${idIn}<input type="hidden" name="to" value="draft">
           <button type="submit">↩ unqueue step</button>
           <span class="kv">${queuedCount} step(s) queued${mode === "immediate" ? "" : " — run.sh @ 01:30"}</span>
         </form>`
      : allDone
        ? `<div class="kv">all ${total} steps done ✓</div>`
        : nextStatus
          ? `<form class="act" method="post" action="/card/queue">${idIn}<input type="hidden" name="to" value="queued">
               <button type="submit">${nextBlocked ? "⚠ force-queue blocked step" : "✅ queue next step"}</button>
               <span class="kv">${nextBlocked
                 ? `next step is <b>blocked</b> (${esc(nextStatus)}) — queue anyway as an override`
                 : `queues the next draft step${mode === "immediate" ? " and runs it now" : "; run.sh @ 01:30 runs it"}`}</span>
             </form>`
          : `<div class="kv">no pending steps</div>`;

  // Explicit immediate run of THIS project (targeted), regardless of mode.
  const runControl = allDone ? "" :
    `<form class="act" method="post" action="/card/run-now">${idIn}
       <button type="submit">▶ run now</button>
       <span class="kv">queues the next step if needed, then runs only this project immediately (targeted run.sh)</span>
     </form>`;

  // Persistent mode toggle. IMMEDIATE = queuing a step kicks a run right away;
  // NIGHTLY = a queued step waits for the 01:30 timer.
  const modeControl =
    `<form class="act" method="post" action="/card/mode">${idIn}<input type="hidden" name="mode" value="${mode === "immediate" ? "nightly" : "immediate"}">
       <button type="submit">${mode === "immediate" ? "🌙 switch to NIGHTLY" : "⚡ switch to IMMEDIATE"}</button>
       <span class="kv">now: <b>${mode === "immediate" ? "⚡ immediate (queue → runs now)" : "🌙 nightly (queue → waits for 01:30)"}</b></span>
     </form>`;

  const body = `<div class="detail">
  <a href="/nightly" class="kv">← nightly</a>
  <h2><span class="swatch" style="background:${color}"></span> ${esc(titleOf(item))} <span class="badge">${mode === "immediate" ? "⚡ immediate" : "🌙 nightly"}</span></h2>
  <div class="kv">project · nightly-build · goal <b>${esc(goalId)}</b> · ${done}/${total} steps</div>
  <div class="bar"><span style="width:${pct}%"></span></div>

  <h2>Queue</h2>
  ${queueControl}

  <h2>Run now</h2>
  ${runControl || '<div class="kv">nothing to run — all steps done ✓</div>'}

  <h2>Mode</h2>
  ${modeControl}

  <h2>Steps</h2>
  <div class="steps">${stepRows || '<div class="empty">no steps</div>'}</div>

  ${goalBody ? `<h2>Goal</h2><div class="md">${mdToHtml(goalBody)}</div>` : ""}
</div>`;
  return layout("nightly", body);
}

/** Render a run's REPORT.md (plain — escaped <pre>). */
export function renderReport(title: string, report: string | null): string {
  const body = `<div class="detail">
  <a href="/" class="kv">← board</a>
  <h2>📄 ${esc(title)} — REPORT</h2>
  ${report ? `<div class="md">${mdToHtml(report)}</div>` : `<div class="empty" style="padding:24px">no REPORT.md found for this run</div>`}
</div>`;
  return layout("", body);
}
