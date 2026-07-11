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

import { Item, Pipeline } from "../contracts.js";
import { PrReview } from "../review/contract.js";
import { ResolvedPipeline } from "../pipelines/catalog.js";
import { DomainRegistry, domainOf } from "../domains.js";
import { mdToHtml } from "./markdown.js";

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string),
  );
}

const NEUTRAL = "#a7aaad"; // HWC palette fg2 (dim) — neutral fallback color
const UNTRIAGED = "untriaged";
function titleOf(item: Item): string {
  return item.payload && typeof item.payload === "object" && "title" in item.payload
    ? String((item.payload as { title: unknown }).title)
    : item.id;
}

const LANES: { status: Item["state"]; label: string }[] = [
  { status: "pending", label: "In Pipeline" },
  { status: "running", label: "Running" },
  { status: "parked", label: "Needs You" },
  { status: "passed", label: "Done" },
  { status: "failed", label: "Failed" },
];

// Hopper lanes = idea-maturation stages (the chain's first half, before an idea
// is promoted into the Gauntlet). Stored in `item.stage` on untriaged items.
export const HOPPER_STAGES: { key: string; label: string }[] = [
  { key: "captured", label: "Captured" },
  { key: "shaping", label: "Shaping" },
  { key: "ready", label: "Ready" },
];
export const HOPPER_STAGE_KEYS = HOPPER_STAGES.map((s) => s.key);
function stageOf(item: Item): string {
  return item.stage && HOPPER_STAGE_KEYS.includes(item.stage) ? item.stage : "captured";
}

// Render context threaded to every card: the domain registry (color/tag), all
// pipelines (for the pipeline label), the promote-target (enabled) pipelines, and
// the `back` path that actions redirect to.
interface CardCtx {
  domains: DomainRegistry;
  profiles: ResolvedPipeline[];
  enabled: ResolvedPipeline[];
  back: string;
}

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
  .asks{margin:4px 0 12px;border-left:3px solid var(--warn);padding:6px 0 6px 12px;background:color-mix(in srgb,var(--warn) 8%,transparent)}
  .asks .askhdr{font-size:12px;font-weight:700;color:var(--warn);text-transform:uppercase;letter-spacing:.04em}
  .asks ol{margin:6px 0 0 18px;padding:0}
  .asks li{margin:4px 0;color:var(--ink);font-size:13px}
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
  .act textarea{flex:1 0 100%;min-width:200px;resize:vertical;font:inherit}
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
  /* OKF vault cross-links: obsidian://open deep links into the brain vault */
  .md .vlink{color:var(--acc2);border-bottom:1px dotted var(--acc2);overflow-wrap:anywhere}
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
  /* per-card gate-dot progress strip: one dot per pipeline step, in order */
  .gate-dots{display:flex;gap:5px;margin-top:7px;align-items:center;flex-wrap:wrap}
  .gate-dot{width:9px;height:9px;border-radius:50%;background:var(--dim);flex:none}
  .gate-dot.passed{background:var(--ok)}
  .gate-dot.parked{background:var(--warn)}
  .gate-dot.failed{background:var(--err)}
  .gate-dot.running{background:var(--acc)}
  .gate-dot.pending{background:var(--dim)}
  .gate-dot.skipped{background:transparent;border:1px solid var(--muted)}
  .gate-dot.current{box-shadow:0 0 0 2px var(--bg),0 0 0 3px var(--ink)}
  /* item pipeline node strip (detail page): Triage → gates → executor → Done */
  .nodes{display:flex;flex-direction:column;gap:6px;margin-top:8px}
  .node{border:1px solid var(--line);border-radius:6px;background:var(--panel)}
  .node summary{display:flex;gap:8px;align-items:center;padding:8px 10px;cursor:pointer;list-style:none}
  .node summary::-webkit-details-marker{display:none}
  .node .nlab{flex:1;color:var(--ink);font-size:13px}
  .node .arrow{color:var(--muted)}
  .node .ndot{width:10px;height:10px;border-radius:50%;background:var(--dim);flex:none}
  .node .ndot.passed{background:var(--ok)}
  .node .ndot.parked{background:var(--warn)}
  .node .ndot.failed{background:var(--err)}
  .node .ndot.running{background:var(--acc)}
  .node .ndot.skipped{background:transparent;border:1px solid var(--muted)}
  .node .nbody{padding:0 12px 10px;font-size:12px;color:var(--dim)}
  .node .nbody b{color:var(--fg)}
</style>`;

function layout(active: string, body: string): string {
  const tab = (href: string, label: string, key: string) =>
    `<a href="${href}" class="${active === key ? "active" : ""}">${label}</a>`;
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Refinery</title>${STYLE}</head><body>
<header><h1>🛠 Refinery</h1><nav>
  ${tab("/", "Board", "flow")}${tab("/nightly", "Overnight", "nightly")}${tab("/finished", "Finished", "finished")}${tab("/sr", "SR", "sr")}${tab("/reviews", "Reviews", "reviews")}${tab("/reference", "Reference", "reference")}
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
const statusOf = (item: Item): string => item.state;
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === "object" ? (v as Record<string, unknown>) : {});

// Each board POST carries `back` so the handler redirects to the board the user
// is on (not the detail page) — they see the card change lane in place.
function backField(back: string): string {
  return `<input type="hidden" name="back" value="${esc(back)}">`;
}

// A domain picker (manual override of the auto-classified color/tag). onchange
// auto-submits → POST /domain. Lists every domain + the fallback.
function domainPicker(item: Item, ctx: CardCtx, idIn: string, bk: string): string {
  const cur = domainOf(item, ctx.domains).key;
  const all = [...ctx.domains.domains, ctx.domains.fallback];
  const opts = all
    .map((d) => `<option value="${esc(d.key)}"${d.key === cur ? " selected" : ""}>${esc(d.label)}</option>`)
    .join("");
  return `<form class="cc" method="post" action="/domain">${idIn}${bk}<select name="domain" title="domain (color + tag)" onchange="this.form.submit()">${opts}</select></form>`;
}

// Inline per-card controls (SR2 ticket-card quick actions, no-framework form
// posts). Kind decides the controls:
//   • read-only nightly mirror → vault-backed queue / run-now / mode
//   • idea → domain picker + stage advance (+ promote when Ready)
//   • engine project → status lane + pipeline re-pick + domain + run + nightly + delete
function controlsFor(item: Item, ctx: CardCtx): string {
  const pl = obj(item.payload);
  const isIdea = item.pipeline === UNTRIAGED;
  const readonly = pl.readonly === true;
  const idIn = `<input type="hidden" name="id" value="${esc(item.id)}">`;
  const bk = backField(ctx.back);

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
    // Stage advance (Captured → Shaping → Ready) + domain picker. A Ready idea
    // promotes into project-ideation, immediate or nightly (the only choice —
    // project-ideation is THE idea→spec refiner; downstream gauntlet routing is
    // a later auto-step). Below Ready, no promote: shape it first.
    const stage = stageOf(item);
    const stageOpts = HOPPER_STAGES.map(
      (s) => `<option value="${s.key}"${stage === s.key ? " selected" : ""}>${esc(s.label)}</option>`,
    ).join("");
    const stageSel = `<form class="cc" method="post" action="/stage">${idIn}${bk}<select name="toStage" title="idea stage" onchange="this.form.submit()">${stageOpts}</select></form>`;
    // Promote redirects to the Gauntlet (back=/) so the new project is seen
    // arriving, not just leaving the Hopper.
    const promote = stage === "ready"
      ? `<form class="cc" method="post" action="/promote">${idIn}<input type="hidden" name="back" value="/"><input type="hidden" name="pipeline" value="project-ideation">
           <button type="submit" name="schedule" value="immediate" title="refine into a spec now">→ refine now</button>
           <button type="submit" name="schedule" value="nightly" title="queue for the overnight run">🌙 nightly</button>
         </form>`
      : "";
    const delBtn = `<form class="cc" method="post" action="/delete">${idIn}${bk}<button type="submit" class="danger" title="delete idea">🗑</button></form>`;
    return `<div class="ccrow">${stageSel}${domainPicker(item, ctx, idIn, bk)}${promote}${delBtn}</div>`;
  }

  // engine project: change lane (status), re-pick pipeline, domain, run,
  // nightly toggle, delete.
  const isNightly = item.schedule === "nightly";
  const statusOpts = STATUS_LANES.map(
    (l) => `<option value="${l.key}"${item.state === l.key ? " selected" : ""}>${esc(l.label)}</option>`,
  ).join("");
  const statusSel = `<form class="cc" method="post" action="/status">${idIn}${bk}<select name="status" title="move to lane" onchange="this.form.submit()">${statusOpts}</select></form>`;
  const pipelineOpts = ctx.enabled
    .map((p) => `<option value="${esc(p.pipeline)}"${p.pipeline === item.pipeline ? " selected" : ""}>${esc(p.label)}</option>`)
    .join("");
  const pipelineSel = ctx.enabled.length
    ? `<form class="cc" method="post" action="/promote">${idIn}${bk}<select name="pipeline" title="pipeline" onchange="this.form.submit()">${pipelineOpts}</select></form>`
    : "";
  const runBtn = item.state === "running"
    ? `<span class="badge">running…</span>`
    : `<form class="cc" method="post" action="/run">${idIn}${bk}<button type="submit" title="run the pipeline now">▶</button></form>`;
  const nightlyBtn = `<form class="cc" method="post" action="/nightly/toggle">${idIn}${bk}<input type="hidden" name="nightly" value="${isNightly ? "false" : "true"}"><button type="submit" title="${isNightly ? "remove from nightly" : "run overnight"}">${isNightly ? "🌙✓" : "🌙"}</button></form>`;
  const delBtn = `<form class="cc" method="post" action="/delete">${idIn}${bk}<button type="submit" class="danger" title="delete project">🗑</button></form>`;
  return `<div class="ccrow">${statusSel}${pipelineSel}${domainPicker(item, ctx, idIn, bk)}${runBtn}${nightlyBtn}${delBtn}</div>`;
}

// The full step sequence of a pipeline = its gates, then its terminal executor
// id. This is the canonical ordering the gate-dot strip + the detail node strip
// both walk.
function pipelineSteps(p: ResolvedPipeline | Pipeline | undefined): string[] {
  if (!p) return [];
  return [...p.gates, ...(p.executors[0] ? [p.executors[0]] : [])];
}

// Map a history-status onto a gate-dot CSS state class. History statuses are
// State | "rewound" | "entered"; only the State ones carry a color.
function dotStateFromStatus(status: string): string {
  if (status === "passed" || status === "parked" || status === "failed" || status === "running") return status;
  return "pending"; // pending / entered / rewound → neutral
}

// Per-step state for the dot strip = the LAST matching history entry's status
// for that step (mapped to a dot state); no history for a step → "pending".
// On a COMPLETED pipeline (state=passed) a step that never ran is "skipped"
// (e.g. a gate whose applies() was false), not "pending" — otherwise a finished
// item looks stuck mid-pipeline.
function stepStates(item: Item, steps: string[]): Map<string, string> {
  const m = new Map<string, string>();
  for (const s of steps) m.set(s, "pending");
  for (const h of item.history) {
    if (m.has(h.step)) m.set(h.step, dotStateFromStatus(h.status));
  }
  if (item.state === "passed") {
    for (const s of steps) if (m.get(s) === "pending") m.set(s, "skipped");
  }
  return m;
}

/** Gate-dot progress strip — one dot per pipeline step (gates + executor id), in
 *  order. Color = the step's last history state; the current `item.step` wears a
 *  ring. Ideas (untriaged, no pipeline) get nothing. Pure CSS. */
function gateDots(item: Item, ctx: CardCtx): string {
  if (item.pipeline === UNTRIAGED) return "";
  const pipeline = ctx.profiles.find((p) => p.pipeline === item.pipeline);
  const steps = pipelineSteps(pipeline);
  if (!steps.length) return "";
  const states = stepStates(item, steps);
  const dots = steps
    .map((s) => {
      const st = states.get(s) ?? "pending";
      const cur = item.step === s ? " current" : "";
      return `<span class="gate-dot ${st}${cur}" title="${esc(`${s}: ${st}`)}"></span>`;
    })
    .join("");
  return `<div class="gate-dots" title="pipeline steps">${dots}</div>`;
}

function cardLink(item: Item, ctx: CardCtx): string {
  const dom = domainOf(item, ctx.domains);
  const color = dom.color;
  const c = esc(color);
  const isIdea = item.pipeline === UNTRIAGED;
  const isNightly = item.schedule === "nightly";
  const pl = obj(item.payload);
  const moon = isNightly ? `<span class="moon" title="nightly">🌙</span>` : "";
  const goal = typeof pl.goal === "string" ? pl.goal : "";
  const customer = typeof pl.customer === "string" ? pl.customer : "";
  const question = typeof pl.title === "string" ? pl.title : "";
  const hasReport = pl.hasReport === true;
  const total = typeof pl.stepsTotal === "number" ? pl.stepsTotal : 0;
  const doneN = typeof pl.stepsDone === "number" ? pl.stepsDone : 0;

  // Identity badge = DOMAIN (color + tag), persistent across the chain. Then the
  // pipeline as a neutral badge (projects only), plus goal/step/report.
  // Lane (column) encodes stage/status; color stays the domain (type) axis.
  const domainTag = `<span class="badge type" style="color:${c};background:color-mix(in srgb,${c} 18%,transparent);border-color:color-mix(in srgb,${c} 40%,transparent)">${esc(dom.label)}</span>`;
  const pipelineLabel = ctx.profiles.find((p) => p.pipeline === item.pipeline)?.label ?? item.pipeline;
  const pipelineBadge = isIdea ? "" : `<span class="badge" title="pipeline">${esc(pipelineLabel)}</span>`;
  const goalBadge = goal ? `<span class="badge">${esc(goal)}</span>` : "";
  const stepBadge = isIdea || !item.step ? "" : `<span class="badge">${esc(item.step)}</span>`;
  const reportBadge = hasReport ? `<span class="badge" title="has REPORT">📄</span>` : "";

  const bar = total > 0
    ? `<div class="bar"><span style="width:${Math.round((doneN / total) * 100)}%"></span></div><div class="kv" style="font-size:11px;margin-top:3px">${doneN}/${total} steps done</div>`
    : "";

  // Title = who/what; for an SR the customer is the "who" and the question the
  // "why it matters". Otherwise the payload title (or id) is the title.
  const title = customer || titleOf(item);
  const why = customer && question ? `<div class="why">${esc(question)}</div>` : "";

  // SR2 ticket-card edge: domain-color left border + faint domain-tinted fill,
  // color-mix over --elev so the tint reads on the dark surface.
  const skin = `border-left-color:${c};background:color-mix(in srgb,${c} 12%,var(--elev))`;

  // Card is a container (not a link) so it can hold interactive controls; the
  // title is the click-through to the detail page.
  return `<div class="card${isNightly ? " nightly" : ""}" style="${skin}">
    <div class="badges">${domainTag}${pipelineBadge}${goalBadge}${stepBadge}${reportBadge}${moon}</div>
    <a class="title" href="/project/${esc(item.id)}">${esc(title)}</a>
    ${why}
    ${bar}
    ${gateDots(item, ctx)}
    ${item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : ""}
    ${controlsFor(item, ctx)}
  </div>`;
}

// Shared status-lane board: cards grouped into columns. Lane (column) = the
// stage/status axis; card color = the domain (identity) axis. Every board page.
function laneBoard(
  projects: Item[],
  ctx: CardCtx,
  lanes: { key: string; label: string }[],
  keyOf: (item: Item) => string,
): string {
  const cols = lanes
    .map((lane) => {
      const inLane = projects.filter((p) => keyOf(p) === lane.key);
      const body = inLane.length ? inLane.map((p) => cardLink(p, ctx)).join("") : `<div class="empty">—</div>`;
      return `<section class="col"><h2>${esc(lane.label)} <span class="count">${inLane.length}</span></h2><div class="cards">${body}</div></section>`;
    })
    .join("");
  return `<div class="board">${cols}</div>`;
}

const emptyRegistry: DomainRegistry = { domains: [], fallback: { key: "misc", label: "Misc", color: NEUTRAL, match: [] } };

/** Flow board: triaged PROJECTS in state lanes, colored by domain. Each card's
 *  gate-dot strip makes the engine's pipeline progress visible at a glance. */
export function renderFlowBoard(
  projects: Item[],
  profiles: ResolvedPipeline[],
  enabled: ResolvedPipeline[] = [],
  domains: DomainRegistry = emptyRegistry,
): string {
  const ctx: CardCtx = { domains, profiles, enabled, back: "/" };
  return layout("flow", `<div class="wrap">${laneBoard(projects, ctx, STATUS_LANES, statusOf)}</div>`);
}

/** Hopper: untriaged IDEAS in maturation-stage lanes (Captured → Shaping →
 *  Ready) + the intake box. Stage = lane; domain = color/tag. A Ready idea
 *  promotes into the Gauntlet. */
export function renderHopperPage(
  ideas: Item[],
  profiles: ResolvedPipeline[],
  enabled: ResolvedPipeline[] = [],
  domains: DomainRegistry = emptyRegistry,
): string {
  const ctx: CardCtx = { domains, profiles, enabled, back: "/hopper" };
  const board = laneBoard(ideas, ctx, HOPPER_STAGES, stageOf);
  const body = `
<form class="intake" method="post" action="/intake">
  <input type="text" name="text" placeholder="Capture an idea — it lands here (and in the brain backlog); shape it, then promote it when Ready…" required autofocus>
  <button type="submit">→ hopper</button>
</form>
<div class="wrap">${ideas.length ? board : '<div class="empty" style="padding:24px">no ideas waiting — type one above</div>'}</div>`;
  return layout("hopper", body);
}

/** Board: the two stacked kanbans on one page (the assembly-line view). The
 *  intake box, then **Hopper** (untriaged IDEAS in maturation-stage lanes) on
 *  top, then **Development** (triaged PROJECTS in state lanes) below. One page,
 *  two boards — an idea matures in the Hopper, gets promoted, then runs through
 *  the pipeline in Development. Each board reuses laneBoard; section headers name
 *  them. */
export function renderBoard(
  ideas: Item[],
  projects: Item[],
  profiles: ResolvedPipeline[],
  enabled: ResolvedPipeline[] = [],
  domains: DomainRegistry = emptyRegistry,
): string {
  const hopperCtx: CardCtx = { domains, profiles, enabled, back: "/" };
  const devCtx: CardCtx = { domains, profiles, enabled, back: "/" };
  const hopperBoard = ideas.length
    ? laneBoard(ideas, hopperCtx, HOPPER_STAGES, stageOf)
    : '<div class="empty" style="padding:16px">no ideas waiting — capture one above</div>';
  const devBoard = projects.length
    ? laneBoard(projects, devCtx, STATUS_LANES, statusOf)
    : '<div class="empty" style="padding:16px">no projects yet — promote a Ready idea from the Hopper</div>';
  const body = `
<form class="intake" method="post" action="/intake">
  <input type="text" name="text" placeholder="Capture an idea — it lands in the Hopper (and the brain backlog); shape it, then promote it when Ready…" required autofocus>
  <button type="submit">→ hopper</button>
</form>
<div class="wrap" style="flex-direction:column">
  <h2 style="width:100%;margin:0 0 2px;font-size:14px;color:var(--ink)">Hopper — ideas <span class="kv" style="font-weight:400">capture → shape → promote</span></h2>
  ${hopperBoard}
  <h2 style="width:100%;margin:14px 0 2px;font-size:14px;color:var(--ink)">Development — projects <span class="kv" style="font-weight:400">spec → build, gate by gate</span></h2>
  ${devBoard}
</div>`;
  return layout("flow", body);
}

/** Nightly: projects flagged nightly, as a status-lane kanban with a per-night
 *  cap. Each card carries its queue/run/mode controls inline. */
export function renderNightly(
  nightly: Item[],
  maxPerNight: number,
  profiles: ResolvedPipeline[],
  enabled: ResolvedPipeline[] = [],
  domains: DomainRegistry = emptyRegistry,
): string {
  const ctx: CardCtx = { domains, profiles, enabled, back: "/nightly" };
  const queuedProjects = nightly.filter((i) => ((i.payload as { queuedCount?: number })?.queuedCount ?? 0) > 0).length;
  const board = laneBoard(nightly, ctx, STATUS_LANES, statusOf);
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
  profiles: ResolvedPipeline[],
  enabledProfiles: ResolvedPipeline[],
  domains: DomainRegistry = emptyRegistry,
): string {
  const isIdea = item.pipeline === UNTRIAGED;
  const color = domainOf(item, domains).color;
  const isNightly = item.schedule === "nightly";
  const pipeline = profiles.find((p) => p.pipeline === item.pipeline);
  const targets = pipeline
    ? (() => {
        const idx = item.step ? pipeline.gates.indexOf(item.step) : -1;
        return idx > 0 ? pipeline.gates.slice(0, idx) : pipeline.gates.filter((g) => g !== item.step);
      })()
    : [];

  // Timeline (was "History"): each entry with a small state dot.
  const timeline = item.history.length
    ? item.history.map((h) => `<div class="hist"><span class="gate-dot ${dotStateFromStatus(h.status)}" style="display:inline-block;vertical-align:middle;margin-right:6px"></span>${esc(h.at)} · <b>${esc(h.step)}</b> · ${esc(h.status)}${h.note ? ` — ${esc(h.note)}` : ""}</div>`).join("")
    : `<div class="hist">—</div>`;

  // Pipeline node strip: Triage → <each gate> → <executor> → Done. Each node is
  // a <details> that expands to its persisted verdict (gates) / executor result
  // (terminal) / triage decision. State dot from the last matching history entry.
  const pipelineNodes = (() => {
    if (isIdea || !pipeline) return "";
    const steps = pipelineSteps(pipeline); // gates + executor id
    const states = stepStates(item, steps);
    const pl = obj(item.payload);
    const verdicts = obj(pl.verdicts);
    const execResult = obj(pl.executorResult);
    const triage = obj(pl.triage);
    const executorId = pipeline.executors[0] ?? "";

    const dot = (st: string) => `<span class="ndot ${st}"></span>`;
    const node = (label: string, st: string, bodyHtml: string) =>
      `<details class="node"><summary>${dot(st)}<span class="nlab">${esc(label)}</span><span class="kv">${esc(st)}</span></summary><div class="nbody">${bodyHtml}</div></details>`;
    const arrow = `<div class="arrow" style="text-align:center;color:var(--muted)">↓</div>`;

    const prettyOutput = (v: unknown): string => {
      if (v == null) return "";
      if (typeof v === "string") return `<div class="md">${mdToHtml(v)}</div>`;
      return `<pre>${esc(JSON.stringify(v, null, 2))}</pre>`;
    };

    // Triage node — confidence + reason from payload.triage.
    const triageBody = Object.keys(triage).length
      ? `${typeof triage.confidence === "number" ? `<div><b>confidence:</b> ${triage.confidence}</div>` : ""}${typeof triage.reason === "string" ? `<div><b>reason:</b> ${esc(triage.reason)}</div>` : ""}`
      : `<div class="kv">no triage record</div>`;
    const triageNode = node("Triage", "passed", triageBody);

    // Gate nodes — each gate's full verdict from payload.verdicts[step].
    const gateNodes = pipeline.gates
      .map((g) => {
        const v = obj(verdicts[g]);
        const st = states.get(g) ?? "pending";
        const body = Object.keys(v).length
          ? `${v.decision != null ? `<div><b>decision:</b> ${esc(String(v.decision))}</div>` : ""}${v.reason != null ? `<div><b>reason:</b> ${esc(String(v.reason))}</div>` : ""}${prettyOutput(v.output)}`
          : st === "skipped"
            ? `<div class="kv">skipped — this gate did not apply to the item</div>`
            : `<div class="kv">no verdict recorded for this step</div>`;
        return node(g, st, body);
      })
      .join(arrow);

    // Executor node — payload.executorResult.
    const branch = typeof execResult.branch === "string" ? execResult.branch : "";
    const execBody = Object.keys(execResult).length
      ? `${execResult.outcome != null ? `<div><b>outcome:</b> ${esc(String(execResult.outcome))}</div>` : ""}${execResult.verdict != null ? `<div><b>verdict:</b> ${esc(String(execResult.verdict))}</div>` : ""}${branch ? `<div><b>branch:</b> ${esc(branch)}</div>` : ""}${"pushed" in execResult ? `<div><b>pushed:</b> ${String(execResult.pushed)}</div>` : ""}${"pristine" in execResult ? `<div><b>pristine:</b> ${String(execResult.pristine)}</div>` : ""}${"reportPresent" in execResult ? `<div><b>report:</b> ${String(execResult.reportPresent)}</div>` : ""}${execResult.detail != null ? `<div><b>detail:</b> ${esc(String(execResult.detail))}</div>` : ""}${prettyOutput(execResult.output)}`
      : `<div class="kv">not yet executed</div>`;
    const execNode = executorId
      ? node(`Executor · ${executorId}`, states.get(executorId) ?? "pending", execBody)
      : "";

    const doneNode = node("Done", item.state === "passed" ? "passed" : "pending", `<div class="kv">${item.state === "passed" ? "pipeline complete" : "not finished"}</div>`);

    return `<h2>Pipeline</h2><div class="nodes">${triageNode}${arrow}${gateNodes}${execNode ? arrow + execNode : ""}${arrow}${doneNode}</div>`;
  })();

  const promote = isIdea
    ? `<h2>Promote to a project</h2>
       <form class="act" method="post" action="/promote">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <select name="pipeline">${enabledProfiles.map((p) => `<option value="${esc(p.pipeline)}">${esc(p.label)}</option>`).join("")}</select>
         <button type="submit">promote →</button>
       </form>`
    : "";

  const parkedActions = (() => {
    if (item.state !== "parked") {
      return `<div class="kv">No human action needed at this step (${esc(item.state)}).</div>`;
    }
    // The gate that parked this step records its verdict (incl. `asks` — the
    // concrete decisions the human must make) at payload.verdicts[step].output.
    const pv = obj(obj(obj(item.payload).verdicts)[item.step ?? ""]);
    const rawAsks = obj(pv.output).asks;
    const asks = Array.isArray(rawAsks) ? rawAsks.filter((a) => typeof a === "string") as string[] : [];
    const askList = asks.length
      ? `<div class="asks"><div class="askhdr">To unblock, decide:</div><ol>${asks.map((a) => `<li>${esc(a)}</li>`).join("")}</ol></div>`
      : `<div class="kv" style="margin-bottom:8px">This step needs a human call — answer below to re-arm and continue, or rewind to revisit an earlier step. (No structured asks recorded${pv.output ? "" : "; this item ran before asks were captured — re-run to get them"}.)</div>`;
    return `${askList}
         <form class="act" method="post" action="/amend">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <input type="text" name="note" placeholder="${asks.length ? "your decision(s) — answering the asks above re-arms the step" : "your decision / answer (re-arms the step)"}" required>
           <button type="submit">✎ answer &amp; continue</button>
         </form>
         ${targets.length ? `<form class="act" method="post" action="/rewind">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <select name="toStep">${targets.map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join("")}</select>
           <input type="text" name="note" placeholder="why rewind?" required>
           <button type="submit">⟲ rewind</button>
         </form>` : ""}`;
  })();

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

  // Run button — triggers the engine pipeline (gates → executor) for a triaged
  // engine item. Read-only mirror items (nightly/SR cards) execute via their own
  // gauntlets, so they don't get it.
  // Native pipelines (app-refinement) execute against a target repo; the board
  // runs the gates then spools execution. Surface a repo picker — prominent and
  // required when unset, since the run fails cleanly without it.
  const usesNative = !isIdea && !!pipeline && pipeline.executors.includes("native") && !readonly;
  const curRepo = typeof payloadObj.repo === "string" ? payloadObj.repo : "";
  const repoBlock = usesNative
    ? `<h2>Target repo${curRepo ? "" : " ⚠"}</h2>
       <form class="act" method="post" action="/set-repo">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <input type="text" name="repo" value="${esc(curRepo)}" placeholder="/home/eric/600_apps/<app>" ${curRepo ? "" : "required"}>
         <button type="submit">${curRepo ? "update repo" : "set repo"}</button>
         <span class="kv">${curRepo ? "the app this pipeline refines (worktree + push target)" : "⚠ required — this pipeline can't execute until you bind the target app repo"}</span>
       </form>`
    : "";

  const execId = (pipeline && pipeline.executors[0]) || "";
  const runHint = execId === "native"
    ? "runs the gates here, then queues native execution (worktree → claude → push)"
    : `runs ${esc(pipeline?.gates.join(" → ") ?? "")}; writes a developed spec`;
  // The prominent Run block is for items that haven't completed. A passed item
  // leads with its Outcome (below) and offers only a muted re-run.
  const runBlock = (!isIdea && pipeline && !readonly && item.state !== "passed")
    ? item.state === "running"
      ? `<h2>Run</h2><div class="kv">⏳ running the ${esc(item.pipeline)} pipeline (${esc(pipeline.gates.join(" → "))})… refresh to see the result.</div>`
      : `<h2>Run</h2>
         <form class="act" method="post" action="/run">
           <input type="hidden" name="id" value="${esc(item.id)}">
           <button type="submit">▶ run pipeline now</button>
           <span class="kv">${runHint}</span>
         </form>`
    : "";

  // Outcome — what a COMPLETED item produced + the next step. This is the answer
  // to "what do I do now?" on a passed card (which otherwise dead-ends on "no
  // human action needed"). project-ideation → a developed spec (rendered inline);
  // native → a pushed branch + report.
  const execResult = obj(payloadObj.executorResult);
  const isDone = !isIdea && !readonly && item.state === "passed" && Object.keys(execResult).length > 0;
  const specObj = obj(obj(execResult.output).spec);
  const specPath = typeof (obj(execResult.output).specPath) === "string" ? String(obj(execResult.output).specPath) : "";
  const branchStr = typeof execResult.branch === "string" ? execResult.branch : "";
  const outcomeBody = Object.keys(specObj).length
    ? `<div class="kv" style="margin-bottom:8px">This idea is now a <b>developed spec</b> — nothing more to do in this pipeline. Review it, then build it.</div>
       <div class="md">
         ${specObj.goal ? `<p><b>Goal:</b> ${esc(String(specObj.goal))}</p>` : ""}
         ${Array.isArray(specObj.steps) ? `<p><b>Steps</b></p><ol>${(specObj.steps as unknown[]).map((s) => `<li>${esc(String(s))}</li>`).join("")}</ol>` : ""}
         ${specObj.deliverable ? `<p><b>Deliverable:</b> ${esc(String(specObj.deliverable))}</p>` : ""}
       </div>
       ${specPath ? `<div class="kv">spec written to <code>${esc(specPath)}</code></div>` : ""}
       <div class="kv" style="margin-top:8px"><b>Next:</b> build it — hit <b>▸ build this</b> below to hand the spec to the build pipeline, or flip auto-build on so it happens automatically when a spec is ready.</div>`
    : `<div class="kv">${execResult.detail ? esc(String(execResult.detail)) : "completed"}${branchStr ? ` · branch <code>${esc(branchStr)}</code>${execResult.pushed ? " (pushed)" : ""}` : ""}.</div>
       ${(payloadObj.hasReport || execResult.reportPresent) ? `<div class="act"><a href="/report/${esc(item.id)}">📄 view REPORT</a></div>` : ""}
       <div class="kv" style="margin-top:8px"><b>Next:</b> review the result${branchStr ? " and the pushed branch — open a PR" : ""}.</div>`;
  // Build handoff — on a DONE spec-bearing item, offer the one-shot "▸ build
  // this" (POST /build) and the auto-advance toggle (POST /chain). Only when the
  // item's pipeline declares a `next` AND it produced a spec (it has somewhere to
  // hand off to). On → the build fires automatically when the spec is ready;
  // off → it stops at the spec for review.
  const hasNext = !!pipeline && typeof pipeline.next === "string" && !!pipeline.next;
  const buildBlock = (hasNext && Object.keys(specObj).length)
    ? `<form class="act" method="post" action="/build" style="margin-top:8px">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <button type="submit">▸ build this</button>
         <span class="kv">hands this spec to the <b>${esc(pipeline!.next!)}</b> pipeline now</span>
       </form>
       <form class="act" method="post" action="/chain">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <input type="hidden" name="on" value="${item.chain ? "false" : "true"}">
         <button type="submit">${item.chain ? "⛔ turn auto-build OFF" : "⚙ turn auto-build ON"}</button>
         <span class="kv">${item.chain
           ? "on → when the spec is ready it builds automatically; click to stop at the spec for review"
           : "off → stops at the spec for review; turn on → when the spec is ready it builds automatically"}</span>
       </form>`
    : "";
  const outcomeBlock = isDone
    ? `<h2>✓ Done — outcome</h2>${outcomeBody}
       ${buildBlock}
       <form class="act" method="post" action="/run" style="margin-top:8px">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <button type="submit">↻ re-run</button>
         <span class="kv">re-runs the whole pipeline from the start</span>
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
    : `${outcomeBlock}${promote}${repoBlock}${runBlock}
  <h2>Human-in-the-loop</h2>
  ${parkedActions}

  <h2>Schedule</h2>
  <form class="act" method="post" action="/nightly/toggle">
    <input type="hidden" name="id" value="${esc(item.id)}">
    <input type="hidden" name="nightly" value="${isNightly ? "false" : "true"}">
    <button type="submit">${isNightly ? "🌙 remove from nightly" : "🌙 run overnight"}</button>
    <span class="kv">${isNightly ? "queued for the overnight gauntlet run" : "runs only when advanced manually / on a beat"}</span>
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
  <div class="kv">${isIdea ? "idea (untriaged)" : `project · ${esc(item.pipeline)}`}${goal ? ` · goal: <b>${esc(goal)}</b>` : ""} · step <b>${esc(item.step ?? item.stage ?? "—")}</b> · ${esc(item.state)} ${isNightly ? "· 🌙 nightly" : ""}</div>
  ${item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : ""}
  ${input ? `<div class="md"><p><em>${esc(input)}</em></p></div>` : ""}

  ${actions}

  ${cardBody ? `<h2>Card</h2><div class="md">${mdToHtml(cardBody)}</div>` : ""}

  ${pipelineNodes}

  <h2>Payload</h2>
  <pre>${esc(JSON.stringify(item.payload, null, 2))}</pre>

  <h2>Timeline</h2>
  ${timeline}
</div>`;
  return layout("", body);
}

/** SR page: investigations as a status-lane kanban (cards = customer + question
 *  → tabbed detail). Lanes are the distinct SR statuses (data-driven), so a new
 *  status needs no renderer edit. */
export function renderSr(
  srs: Item[],
  maxPerNight: number,
  profiles: ResolvedPipeline[],
  domains: DomainRegistry = emptyRegistry,
): string {
  const srStatusOf = (item: Item): string => {
    const p = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
    return typeof p.srStatus === "string" && p.srStatus ? p.srStatus : "investigated";
  };
  const lanes = [...new Set(srs.map(srStatusOf))].sort().map((s) => ({ key: s, label: s }));
  // SR cards are read-only mirrors (no inline controls); run-now lives on detail.
  const ctx: CardCtx = { domains, profiles, enabled: [], back: "/sr" };
  const board = laneBoard(srs, ctx, lanes, srStatusOf);
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

/** Finished: graduated projects (all steps done, off the gauntlet). They're all
 *  "passed", so a status-lane board would dump them in one lane — a plain grid
 *  reads better. Reuse cardLink so a finished card clicks through to its
 *  read-only detail (/project/nbf:<goal>). */
export function renderFinished(
  finished: Item[],
  profiles: ResolvedPipeline[] = [],
  enabled: ResolvedPipeline[] = [],
  domains: DomainRegistry = emptyRegistry,
): string {
  const ctx: CardCtx = { domains, profiles, enabled, back: "/finished" };
  const cards = finished.map((p) => cardLink(p, ctx)).join("");
  const body = `
<div class="intake"><span class="kv">${finished.length} finished project${finished.length === 1 ? "" : "s"} — graduated off the gauntlet. Open one to send it back with amendments.</span></div>
<div class="wrap">${finished.length ? cards : '<div class="empty" style="padding:24px">no finished projects yet</div>'}</div>`;
  return layout("finished", body);
}

/** Finished-project detail: a READ-ONLY mirror of renderNightlyProject (no
 *  queue/run/mode controls — the project is graduated). Surfaces each step's PR
 *  link, plus a "send back with amendments" form that reopens it on the
 *  gauntlet. */
export function renderFinishedProject(item: Item): string {
  const p = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
  const color = "#cf995f"; // HWC palette: warning (copper) — nightly-build tint
  const steps = Array.isArray(p.steps) ? (p.steps as NbStepView[]) : [];
  const done = typeof p.stepsDone === "number" ? p.stepsDone : 0;
  const total = typeof p.stepsTotal === "number" ? p.stepsTotal : steps.length;
  const goalId = typeof p.goal === "string" ? p.goal : "";
  const goalBody = typeof p.goalBody === "string" ? p.goalBody : "";
  const pct = total > 0 ? Math.round((done / total) * 100) : 0;

  // A step's `pr` is often `branch \`x\` (...)` prose, sometimes a bare URL.
  // Render escaped; linkify only when it's plainly an http(s) URL.
  const prView = (pr: string): string => {
    if (!pr) return "";
    const url = /^https?:\/\/\S+$/.test(pr.trim());
    const inner = url
      ? `<a class="kv" href="${esc(pr.trim())}" rel="noreferrer">${esc(pr.trim())}</a>`
      : `<span class="kv">${esc(pr)}</span>`;
    return `<div class="kv" style="margin-left:30px;margin-top:-2px">${inner}</div>`;
  };

  const stepRows = steps
    .map((s) => {
      const reportLink = s.run ? `<a class="kv" href="/report/${encodeURIComponent("nbrun:" + s.run)}" title="REPORT">📄</a>` : "";
      return `<div class="step">
        <span class="n">${esc(s.n)}</span>
        <span class="ti">${esc(s.title)}${s.step ? ` <span class="kv">(${esc(s.step)})</span>` : ""}</span>
        ${reportLink}
        <span class="st ${stepClass(s.status)}">${esc(s.status)}</span>
      </div>${prView(s.pr)}`;
    })
    .join("");

  const idIn = `<input type="hidden" name="id" value="${esc(item.id)}">`;
  // Send back to the gauntlet, optionally with an amendment (a fresh queued
  // step). Empty amendment = just reopen. back=/finished so the card is seen
  // leaving the Finished page.
  const sendback = `<form class="act" method="post" action="/card/sendback">${idIn}
       <input type="hidden" name="back" value="/finished">
       <textarea name="amendment" rows="3" placeholder="what to change / add — leave empty to just reopen"></textarea>
       <button type="submit">↩ send back to gauntlet</button>
       <span class="kv">reopens this project on the gauntlet; a non-empty note becomes a fresh queued step</span>
     </form>`;

  const body = `<div class="detail">
  <a href="/finished" class="kv">← finished</a>
  <h2><span class="swatch" style="background:${color}"></span> ${esc(titleOf(item))} <span class="badge">✓ finished</span></h2>
  <div class="kv">project · nightly-build · goal <b>${esc(goalId)}</b> · ${done}/${total} steps</div>
  <div class="bar"><span style="width:${pct}%"></span></div>

  <h2>Steps</h2>
  <div class="steps">${stepRows || '<div class="empty">no steps</div>'}</div>

  <h2>Send back with amendments</h2>
  ${sendback}

  ${goalBody ? `<h2>Goal</h2><div class="md">${mdToHtml(goalBody)}</div>` : ""}
</div>`;
  return layout("finished", body);
}

// The canon glossary — the source of truth for the UI's vocabulary. Data-driven
// (a table rendered from this list, not hardcoded rows), so a term added here
// shows up on /reference with no template edit.
const GLOSSARY: { term: string; def: string }[] = [
  { term: "Pipeline", def: "The data-driven recipe for one kind of work — which steps fire, in what executor mode, with which executor and LLM." },
  { term: "Step", def: "A single position in a pipeline: a gate, Triage, or the terminal executor id." },
  { term: "Stage", def: "Hopper-only idea maturation: Captured → Shaping → Ready (before promotion to a project)." },
  { term: "State", def: "An item's execution state at its current step: pending, running, passed, parked, or failed." },
  { term: "Executor", def: "The side-effecting terminal step of a pipeline. native = in-process worktree + headless Claude; gauntlet = dispatch to an external standalone gauntlet; spec = synthesize and write a spec." },
  { term: "executorMode", def: "How the executor runs: read-only vs write (commits/pushes a branch)." },
  { term: "Schedule", def: "The 'when' axis, orthogonal to the pipeline: Now (on demand) or Overnight (the unattended batch)." },
  { term: "Domain", def: "The identity axis — a card's color + tag, persistent across the pipeline." },
  { term: "Idea / Project", def: "An Idea is untriaged (lives in the Hopper). A Project is triaged into a pipeline (lives on the Flow board)." },
  { term: "Gate", def: "A pre-executor check that passes, parks (needs you), or fails an item at a step." },
  { term: "Triage", def: "The classification that routes an idea into a pipeline, with a confidence + reason." },
  { term: "Flow board", def: "The main board — triaged Projects in state lanes, each card showing its gate-dot progress." },
];

/** Reference: a static glossary of the canon + the live pipelines from the
 *  catalog (label, gates in order, executor + mode, enabled). Data-driven. */
export function renderReference(pipelines: ResolvedPipeline[]): string {
  const rows = GLOSSARY.map(
    (g) => `<tr><td style="white-space:nowrap;vertical-align:top"><b>${esc(g.term)}</b></td><td>${esc(g.def)}</td></tr>`,
  ).join("");
  const plRows = pipelines.length
    ? pipelines
        .map(
          (p) => `<tr>
            <td style="vertical-align:top"><b style="color:${esc(p.color)}">${esc(p.label)}</b><div class="kv">${esc(p.pipeline)}</div></td>
            <td style="vertical-align:top">${p.gates.map((gn) => `<span class="badge">${esc(gn)}</span>`).join(" ")}</td>
            <td style="vertical-align:top;white-space:nowrap">${esc(p.executors.join(", "))}<div class="kv">${esc(p.executorMode)}</div></td>
            <td style="vertical-align:top">${p.enabled ? "✓" : "—"}</td>
          </tr>`,
        )
        .join("")
    : `<tr><td colspan="4" class="empty">no pipelines on disk</td></tr>`;
  const body = `<div class="detail" style="max-width:920px">
  <h2>Glossary</h2>
  <table style="width:100%;border-collapse:collapse" class="ref">
    <thead><tr><th style="text-align:left;padding:6px 8px;color:var(--dim)">Term</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Definition</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <h2>Live pipelines</h2>
  <table style="width:100%;border-collapse:collapse" class="ref">
    <thead><tr><th style="text-align:left;padding:6px 8px;color:var(--dim)">Pipeline</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Gates (in order)</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Executor</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Enabled</th></tr></thead>
    <tbody>${plRows}</tbody>
  </table>
</div>`;
  return layout("reference", body);
}

// PR-review lanes, by status (the canon set from review/contract.ts). A new
// status would need a lane added here, but the set is closed (Zod enum).
const REVIEW_LANES: { key: PrReview["status"]; label: string }[] = [
  { key: "needs-you", label: "Needs You" },
  { key: "merged", label: "Merged" },
  { key: "requeued", label: "Requeued" },
  { key: "rejected", label: "Rejected" },
];

function reviewCard(r: PrReview): string {
  const prLink = r.prUrl
    ? `<a class="md" style="color:var(--acc2)" href="${esc(r.prUrl)}" rel="noreferrer">${esc(r.prUrl)}</a>`
    : `<span class="kv">no PR yet</span>`;
  const risks = r.risks.length
    ? `<ul style="margin:6px 0 0 16px;padding:0">${r.risks.map((x) => `<li class="kv">${esc(x)}</li>`).join("")}</ul>`
    : "";
  return `<div class="card" style="border-left-color:var(--acc2)">
    <div class="badges">
      <span class="badge type">${esc(r.verdict)}</span>
      <span class="badge" title="repo">${esc(r.repo)}</span>
    </div>
    <a class="title" href="/project/${esc(r.id)}">${esc(r.title)}</a>
    ${r.recommendation ? `<div class="reason">${esc(r.recommendation)}</div>` : ""}
    <div class="why" style="margin-top:6px">${prLink}</div>
    ${risks}
  </div>`;
}

/** Reviews: morning PR reviews grouped into lanes by status. Each card shows
 *  title, repo, verdict, recommendation, a PR link, and risks. Empty → an
 *  empty state (the reviews dir may be absent / unwritten). */
export function renderReviews(reviews: PrReview[]): string {
  if (!reviews.length) {
    return layout("reviews", `<div class="wrap"><div class="empty" style="padding:24px">no PR reviews yet — the morning review pass writes them after the overnight run pushes branches</div></div>`);
  }
  const cols = REVIEW_LANES.map((lane) => {
    const inLane = reviews.filter((r) => r.status === lane.key);
    const body = inLane.length ? inLane.map(reviewCard).join("") : `<div class="empty">—</div>`;
    return `<section class="col"><h2>${esc(lane.label)} <span class="count">${inLane.length}</span></h2><div class="cards">${body}</div></section>`;
  }).join("");
  return layout("reviews", `<div class="wrap"><div class="board">${cols}</div></div>`);
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
