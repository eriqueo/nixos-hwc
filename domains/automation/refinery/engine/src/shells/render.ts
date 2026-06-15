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
  /* rendered markdown (reports, card bodies) — wraps, doesn't clip */
  .md{max-width:840px;line-height:1.55}
  .md h2,.md h3,.md h4,.md h5{margin:16px 0 6px;font-size:14px;color:var(--ink)}
  .md p{margin:8px 0;overflow-wrap:anywhere}
  .md ul,.md ol{margin:6px 0 6px 20px}
  .md li{margin:3px 0}
  .md code{background:var(--line);padding:1px 4px;border-radius:3px;font-size:12px}
  .md pre.code{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:10px;white-space:pre-wrap;overflow-wrap:anywhere;font-size:12px}
  .md blockquote{border-left:3px solid var(--line);margin:6px 0;padding-left:10px;color:var(--dim)}
  .md a{color:#83a598;overflow-wrap:anywhere}
  /* OKF vault cross-links: styled but non-navigable (board can't resolve vault paths yet) */
  .md .vlink{color:#83a598;border-bottom:1px dotted #83a598;cursor:help;overflow-wrap:anywhere}
  /* SR cards + tabbed detail (mirrors the SR2/datax layout) */
  .srgrid{display:flex;flex-wrap:wrap;gap:12px;padding:14px}
  .srcard{display:block;background:var(--panel);border:1px solid var(--line);border-left:4px solid #83a598;border-radius:8px;padding:10px 12px;width:310px}
  .srcard:hover{border-color:var(--acc)}
  .srcard .cat{font-size:10px;letter-spacing:.05em;text-transform:uppercase;color:#83a598;font-weight:700}
  .srcard .who{font-size:14px;font-weight:600;margin:2px 0}
  .srcard .q{font-size:12px;color:var(--dim);overflow-wrap:anywhere}
  .srtabs{max-width:860px;margin:0 auto;padding:0 18px}
  .srtabs > input{display:none}
  .srhead{padding:14px 0 4px}
  .srhead .cat{font-size:10px;text-transform:uppercase;letter-spacing:.05em;color:#83a598;font-weight:700}
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
  .bar > span{display:block;height:100%;background:var(--done,#b8bb26)}
  .steps{margin-top:8px}
  .step{display:flex;gap:8px;align-items:center;padding:6px 0;border-top:1px solid var(--line);font-size:13px}
  .step .n{color:var(--dim);width:22px;flex:none}
  .step .ti{flex:1;overflow-wrap:anywhere}
  .step .st{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim)}
  .step .st.done{color:#1d2021;background:#b8bb26}
  .step .st.queued,.step .st.running{color:#1d2021;background:var(--acc)}
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
  ${tab("/", "Gauntlet", "gauntlet")}${tab("/hopper", "Hopper", "hopper")}${tab("/nightly", "Nightly", "nightly")}${tab("/sr", "SR", "sr")}
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
  const goal = item.payload && typeof item.payload === "object" && typeof (item.payload as { goal?: unknown }).goal === "string"
    ? (item.payload as { goal: string }).goal
    : "";
  const badge = isIdea
    ? `<span class="badge">idea</span>`
    : `<span class="badge profile" style="background:${esc(color)}">${esc(item.genre)}</span>${goal ? `<span class="badge">${esc(goal)}</span>` : ""}<span class="badge">${esc(item.phase)}</span>`;
  const pl = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
  const total = typeof pl.stepsTotal === "number" ? pl.stepsTotal : 0;
  const doneN = typeof pl.stepsDone === "number" ? pl.stepsDone : 0;
  const bar = total > 0
    ? `<div class="bar"><span style="width:${Math.round((doneN / total) * 100)}%"></span></div><div class="kv" style="font-size:11px;margin-top:3px">${doneN}/${total} steps done</div>`
    : "";
  return `<a class="card${item.nightly ? " nightly" : ""}" href="/project/${esc(item.id)}" style="border-left-color:${esc(color)}">
    <div class="badges">${badge}${moon}</div>
    <div class="title">${esc(titleOf(item))}</div>
    ${bar}
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
  // Projects with a queued step run tonight (run.sh picks up `queued` cards).
  // Sort: queued first, then by progress.
  const sorted = [...nightly].sort((a, b) => {
    const qa = ((a.payload as { queuedCount?: number })?.queuedCount ?? 0) > 0 ? 1 : 0;
    const qb = ((b.payload as { queuedCount?: number })?.queuedCount ?? 0) > 0 ? 1 : 0;
    return qb - qa || a.id.localeCompare(b.id);
  });
  const rows = sorted
    .map((item) => {
      const color = colorOf(item.genre, profiles);
      const p = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
      const queued = typeof p.queuedCount === "number" ? p.queuedCount : 0;
      const done = typeof p.stepsDone === "number" ? p.stepsDone : 0;
      const total = typeof p.stepsTotal === "number" ? p.stepsTotal : 0;
      const hasDraft = Array.isArray(p.steps) && (p.steps as { status: string }[]).some((s) => s.status.toLowerCase().startsWith("draft"));
      const allDone = total > 0 && done === total;
      const btn = queued > 0
        ? `<input type="hidden" name="to" value="draft"><button type="submit">↩ unqueue</button>`
        : hasDraft
          ? `<input type="hidden" name="to" value="queued"><button type="submit">✅ queue next</button>`
          : "";
      return `<div class="nrow${queued > 0 ? " tonight" : ""}">
        <span class="swatch" style="background:${esc(color)}"></span>
        <a class="t" href="/project/${esc(item.id)}">${esc(titleOf(item))} <span class="kv">· ${done}/${total} steps${allDone ? " · ✓ done" : ""}</span></a>
        ${queued > 0 ? '<span class="badge">queued tonight</span>' : ""}
        ${btn ? `<form method="post" action="/card/queue" style="display:inline"><input type="hidden" name="id" value="${esc(item.id)}">${btn}</form>` : ""}
      </div>`;
    })
    .join("");
  const queuedProjects = sorted.filter((i) => ((i.payload as { queuedCount?: number })?.queuedCount ?? 0) > 0).length;
  const body = `
<form class="intake" method="post" action="/nightly/config">
  <label class="kv">Max cards per night:</label>
  <input type="number" name="maxPerNight" min="0" value="${maxPerNight}" style="width:90px">
  <button type="submit">save</button>
  <span class="kv">${nightly.length} projects · ${queuedProjects} with a step queued · run.sh runs up to ${maxPerNight} queued cards @ 01:30</span>
</form>
${rows || '<div class="empty" style="padding:24px">no nightly-build projects</div>'}`;
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

/** SR page: SR2-style cards (customer + question + status) → tabbed detail. */
export function renderSr(srs: Item[], maxPerNight: number, _profiles: ResolvedProfile[]): string {
  const cards = srs
    .map((s) => {
      const p = s.payload && typeof s.payload === "object" ? (s.payload as Record<string, unknown>) : {};
      const customer = typeof p.customer === "string" && p.customer ? p.customer : "—";
      const question = typeof p.title === "string" ? p.title : s.id;
      const cat = typeof p.srStatus === "string" && p.srStatus ? p.srStatus : "investigated";
      return `<a class="srcard" href="/project/${esc(s.id)}">
        <div class="cat">${esc(cat)}${p.hasReport === true ? " · 📄" : ""}</div>
        <div class="who">${esc(customer)}</div>
        <div class="q">${esc(question)}</div>
      </a>`;
    })
    .join("");
  const body = `
<form class="intake" method="post" action="/sr/config">
  <label class="kv">Max SRs per run:</label>
  <input type="number" name="maxPerNight" min="0" value="${maxPerNight}" style="width:90px">
  <button type="submit">save</button>
  <span class="kv">${srs.length} investigations · sr_gauntlet runs @ 06:30 (this cap)</span>
</form>
<div class="srgrid">${cards || '<div class="empty" style="padding:24px">no SR investigations yet — the gauntlet writes them under sr_gauntlet/investigations/</div>'}</div>`;
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
  const color = "#fe8019"; // nightly-build orange
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

  const hasDraft = steps.some((s) => s.status.toLowerCase().startsWith("draft"));
  const queueAction =
    queuedCount > 0
      ? `<form class="act" method="post" action="/card/queue">
           <input type="hidden" name="id" value="${esc(item.id)}"><input type="hidden" name="to" value="draft">
           <button type="submit">↩ unqueue tonight's step</button>
           <span class="kv">${queuedCount} step(s) queued — run.sh @ 01:30 (NB_MAX_CARDS)</span>
         </form>`
      : hasDraft
        ? `<form class="act" method="post" action="/card/queue">
             <input type="hidden" name="id" value="${esc(item.id)}"><input type="hidden" name="to" value="queued">
             <button type="submit">✅ queue next step for tonight</button>
             <span class="kv">queues the next draft step; run.sh @ 01:30 runs it</span>
           </form>`
        : `<div class="kv">no draft steps to queue (${done}/${total} done)</div>`;

  const body = `<div class="detail">
  <a href="/nightly" class="kv">← nightly</a>
  <h2><span class="swatch" style="background:${color}"></span> ${esc(titleOf(item))}</h2>
  <div class="kv">project · nightly-build · goal <b>${esc(goalId)}</b> · ${done}/${total} steps</div>
  <div class="bar"><span style="width:${pct}%"></span></div>

  <h2>Overnight queue</h2>
  ${queueAction}

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
