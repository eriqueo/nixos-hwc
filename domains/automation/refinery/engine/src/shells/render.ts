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

import { currentJudgment, Item, judgmentsFor, Pipeline } from "../contracts.js";
import { PrReview, ReviewCase } from "../review/contract.js";
import { ResolvedPipeline } from "../pipelines/catalog.js";
import { DomainRegistry, domainOf } from "../domains.js";
import { Dx1CasesFile, FleetMember, FleetRates, FleetSnapshot, FleetTemplate, caseStatusLabel, cohortCleanDelta, fleetFamilyColor } from "../sources/dx1-fleet.js";
import { ENHANCER_SCRIPT } from "./enhance.js";
import { GAUNTLET_VIEWS, GauntletRunBundle, GauntletView, detailsExportMd, gauntletViewByKey, tabMd } from "../sources/gauntlet-views.js";
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

function compactText(value: string, max = 220): string {
  const oneLine = value.replace(/\s+/g, " ").trim();
  if (oneLine.length <= max) return oneLine;
  const cut = oneLine.slice(0, max - 1);
  const boundary = cut.lastIndexOf(" ");
  return `${cut.slice(0, boundary > max * 0.7 ? boundary : cut.length).trimEnd()}…`;
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
  now?: number; // ms epoch for age rendering; defaults to wall clock
}

// ── age helpers: history timestamps → card-face age ──
const STALE_AFTER_MS = 14 * 86_400_000; // an idea untouched this long wears the stale skin
function createdAtOf(item: Item): number {
  return item.history.length ? Date.parse(item.history[0]!.at) : NaN;
}
function updatedAtOf(item: Item): number {
  return item.history.length ? Date.parse(item.history[item.history.length - 1]!.at) : NaN;
}
function ageLabel(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) return "";
  const d = Math.floor(ms / 86_400_000);
  if (d >= 1) return `${d}d`;
  const h = Math.floor(ms / 3_600_000);
  return h >= 1 ? `${h}h` : "new";
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
  .btn{display:inline-flex;align-items:center;background:var(--elev);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:6px 10px;cursor:pointer;font-size:12px}.btn.primary{background:color-mix(in srgb,var(--acc) 18%,var(--elev));border-color:var(--acc)}.btn:hover{border-color:var(--acc);color:var(--ink)}
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
  .card.stale{opacity:.72;border-left-style:dotted}
  .badge.age{margin-left:auto;background:transparent;border-color:var(--line);color:var(--muted)}
  .badge.age.old{color:var(--warn);border-color:color-mix(in srgb,var(--warn) 40%,transparent)}
  a.badge:hover{border-color:var(--acc);color:var(--acc)}
  /* board section headers + the GET filter bar + the folded done shelf */
  .secthdr{width:100%;margin:10px 0 2px;font-size:14px;color:var(--ink);display:flex;gap:8px;align-items:baseline}
  .secthdr .count{font-size:12px}
  .secthdr a{color:var(--acc2)}
  .filterbar{display:flex;gap:8px;padding:8px 18px;border-bottom:1px solid var(--line);align-items:center}
  .filterbar select,.filterbar input[type=text]{font-size:12px;padding:5px 8px}
  .filterbar input[type=text]{flex:1;max-width:340px}
  .filterbar button{font-size:12px;padding:5px 10px}
  details.donefold{width:100%}
  details.donefold summary{cursor:pointer;list-style:none}
  details.donefold summary::-webkit-details-marker{display:none}
  details.donefold summary .count::after{content:" ▸"}
  details.donefold[open] summary .count::after{content:" ▾"}
  .badges{display:flex;gap:6px;margin-bottom:5px;flex-wrap:wrap;align-items:center}
  .badge{font-size:10px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--dim);border:1px solid transparent}
  .badge.type{font-weight:700;text-transform:uppercase;letter-spacing:.05em}
  .moon{font-size:12px}
  .title{display:block;font-size:13px;color:var(--ink);font-weight:600;overflow-wrap:anywhere}
  a.title:hover{color:var(--acc)}
  .reason{margin-top:5px;font-size:12px;color:var(--acc);display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;overflow:hidden}
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
  /* fleet cohort-health table (/dx1/fleet) — dx1-health Agents-tab feel */
  .fleet{max-width:1240px;margin:0 auto;padding:0 18px}
  .fleet .meta{color:var(--dim);font-size:13px;margin:6px 0 14px}
  .fleet table{width:100%;border-collapse:collapse;font-size:12px;font-variant-numeric:tabular-nums}
  .fleet th{color:var(--dim);font-weight:500;text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
  .fleet td{padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
  .fleet th.n,.fleet td.n{text-align:right}
  .fleet .sub td{color:var(--dim);border-bottom:1px dashed var(--line)}
  .fleet .sub td:first-child{padding-left:26px}
  .fleet .fam{display:inline-block;border:1px solid;border-radius:8px;padding:0 6px;font-size:11px;margin:0 2px 2px 0;white-space:nowrap}
  .fleet .up{color:var(--ok)} .fleet .down{color:var(--err)}
  .fleet .mtoggle{cursor:pointer;color:var(--acc);user-select:none}
  .fleet tr.mem td{font-size:11px;color:var(--fg);border-bottom:1px dotted var(--line)}
  .fleet tr.mem td:first-child{padding-left:26px}
  .fleet tr.mem b{color:var(--ink);font-weight:600}
  .fleet tr.mem a{color:var(--fg)}
  .fleet tr.mem.quiet td{color:var(--muted)}
  .fleet tr.mem.quiet b{color:var(--muted)}
  .fleet .method{color:var(--muted);font-size:12px;max-width:900px;margin:18px auto 30px;padding:0 18px;border-top:1px solid var(--line)}
  .fleet .method p{margin:8px 0}
  /* DX1 section chrome: one header + tab bar shared by both pages */
  .sechdr{max-width:1240px;margin:14px auto 4px;padding:0 18px;display:flex;align-items:baseline;gap:18px}
  .sechdr h2{margin:0;font-size:16px;color:var(--ink)}
  .subtabs a{color:var(--dim);margin-right:14px;font-size:13px;padding-bottom:3px}
  .subtabs a.active{color:var(--ink);border-bottom:2px solid var(--acc)}
  .sechdr .cfg{margin-left:auto;position:relative}
  .sechdr .cfg summary{cursor:pointer;list-style:none;color:var(--dim)}
  .sechdr .cfg[open] summary{color:var(--ink)}
  .sechdr .cfg .cfgform{position:absolute;right:0;top:22px;background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px;z-index:5;white-space:nowrap}
  .secblock{max-width:1240px;margin:10px auto;padding:0}
  .sechead{max-width:1240px;margin:14px auto 6px;padding:0 18px;font-size:13px;color:var(--ink)}
  .secblock .wrap{margin-top:0}
  .secblock table{margin:0 18px;width:calc(100% - 36px)}
  table.cases{border-collapse:collapse;font-size:12px;font-variant-numeric:tabular-nums}
  table.cases th{color:var(--dim);font-weight:500;text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
  table.cases td{padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
  table.cases th.n,table.cases td.n{text-align:right}
  table.cases b{color:var(--ink);font-weight:600}
  table.cases .fam{display:inline-block;border:1px solid;border-radius:8px;padding:0 6px;font-size:11px;white-space:nowrap}
  table.cases button{font-size:11px;padding:3px 8px}
  .fleet tr.mem.divider td{color:var(--warn);border-bottom:1px solid var(--line);font-size:11px}
  /* sort/filter enhancer chrome (JS-injected; absent without JS) */
  .tfilter{background:var(--elev);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:5px 9px;font-size:12px;margin:8px 8px 8px 0;min-width:200px}
  .fleet .tfilter{display:block}
  th .arr{color:var(--acc);font-size:10px}
  .lanebar{max-width:1500px;margin:0 auto;padding:0 18px;display:flex;align-items:center;flex-wrap:wrap;gap:6px}
  .laneb{font-size:12px;padding:4px 9px;color:var(--dim)}
  .laneb.on{color:var(--ink);border-color:var(--acc)}
  .cardw{display:contents}
  /* Executive workbench hierarchy: answer situation → meaning → action before evidence. */
  .exec-page{width:100%;max-width:1240px;margin:0 auto;padding:16px 18px 28px}
  .exec-hero{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:18px;align-items:center;background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--acc);border-radius:9px;padding:14px 16px;margin-bottom:14px}
  .exec-hero h2{margin:0 0 3px;color:var(--ink);font-size:17px}.exec-hero p{margin:0;color:var(--dim);max-width:760px}
  .exec-stat{font:600 12px/1.3 ui-monospace,monospace;color:var(--ink);text-align:right;white-space:nowrap}
  .exec-section{margin-top:15px}.exec-section>h2{font-size:13px;color:var(--ink);margin:0 0 8px}
  .exec-fold{margin-top:14px;border-top:1px solid var(--line);padding-top:10px}.exec-fold>summary{cursor:pointer;list-style:none;color:var(--dim);font-size:13px;min-height:44px;display:flex;align-items:center}
  .exec-fold>summary::-webkit-details-marker{display:none}.exec-fold>summary::before{content:"▸ ";color:var(--acc);margin-right:5px}.exec-fold[open]>summary::before{content:"▾ "}
  .decision-note{border-left:3px solid var(--warn);padding:8px 11px;background:color-mix(in srgb,var(--warn) 7%,transparent);color:var(--fg);font-size:12px;margin:7px 0}
  .card-actions{margin-top:8px;display:flex;gap:8px;align-items:center}.card-actions>.btn{padding:4px 8px}.card-more{flex:1}.card-more>summary{cursor:pointer;list-style:none;color:var(--dim);font-size:11px;min-height:30px;display:flex;align-items:center}.card-more>summary::-webkit-details-marker{display:none}.card-more>summary::before{content:"＋ ";color:var(--acc)}
  @media(max-width:760px){header{align-items:flex-start;flex-direction:column;gap:8px}nav{display:flex;overflow-x:auto;width:100%}nav a{min-height:44px;display:flex;align-items:center;white-space:nowrap}.exec-page{padding:12px}.exec-hero{grid-template-columns:1fr}.exec-stat{text-align:left}.wrap{padding:8px 0}.grid{grid-template-columns:1fr;padding:0}.ccrow button,.ccrow select,.btn{min-height:44px}}
</style>`;

function layout(active: string, body: string): string {
  const tab = (href: string, label: string, key: string) =>
    `<a href="${href}" class="${active === key ? "active" : ""}">${label}</a>`;
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Refinery</title>${STYLE}</head><body>
<header><h1>🛠 Refinery</h1><nav>
  ${tab("/", "Board", "flow")}${tab("/nightly", "Overnight", "nightly")}${tab("/finished", "Finished", "finished")}${GAUNTLET_VIEWS.map((v) => tab(`/${v.key}`, v.label, v.key)).join("")}${tab("/reviews", "Reviews", "reviews")}${tab("/reference", "Reference", "reference")}
</nav></header>
${body}
${ENHANCER_SCRIPT}
</body></html>`;
}

function executiveHero(headline: string, meaning: string, stat = ""): string {
  return `<section class="exec-hero"><div><h2>${esc(headline)}</h2><p>${esc(meaning)}</p></div>${stat ? `<div class="exec-stat">${esc(stat)}</div>` : ""}</section>`;
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
  // Lineage: a chained successor links back to the spec item it was built from.
  const parentId = typeof pl.parent === "string" ? pl.parent : "";
  const lineageBadge = parentId
    ? `<a class="badge" href="/project/${esc(parentId)}" title="chained from ${esc(parentId)}">⛓ spec</a>`
    : "";
  // Age: time since the last history entry (mirror cards without history show
  // nothing). Stale skin for an idea untouched past the threshold.
  const now = ctx.now ?? Date.now();
  const updatedAge = now - updatedAtOf(item);
  const createdAge = now - createdAtOf(item);
  const age = ageLabel(updatedAge);
  const isStale = isIdea && Number.isFinite(createdAge) && createdAge >= STALE_AFTER_MS;
  const ageBadge = age
    ? `<span class="badge age${isStale ? " old" : ""}" title="last activity">${isStale ? "stale · " : ""}${age}</span>`
    : "";

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
  const needsDecision = item.state === "parked" || item.state === "failed";
  const controls = controlsFor(item, ctx);
  const actionLabel = needsDecision ? "Review decision" : isIdea ? "Shape idea" : "Open";

  // Card is a container (not a link) so it can hold interactive controls; the
  // title is the click-through to the detail page.
  return `<div class="card${isNightly ? " nightly" : ""}${isStale ? " stale" : ""}" style="${skin}">
    <div class="badges">${domainTag}${pipelineBadge}${goalBadge}${stepBadge}${reportBadge}${lineageBadge}${moon}${ageBadge}</div>
    <a class="title" href="/project/${esc(item.id)}">${esc(title)}</a>
    ${why}
    ${bar}
    ${gateDots(item, ctx)}
    ${item.parkedReason ? `<div class="reason">${esc(compactText(item.parkedReason))}</div>` : ""}
    <div class="card-actions"><a class="btn${needsDecision ? " primary" : ""}" href="/project/${esc(item.id)}">${actionLabel}</a>${controls ? `<details class="card-more"><summary>More actions</summary>${controls}</details>` : ""}</div>
  </div>`;
}

// Shared status-lane board: cards grouped into columns. Lane (column) = the
// stage/status axis; card color = the domain (identity) axis. Every board page.
function laneBoard(
  projects: Item[],
  ctx: CardCtx,
  lanes: { key: string; label: string }[],
  keyOf: (item: Item) => string,
  // Optional per-card wrapper attributes (gauntlet pages: data-date for the
  // enhancer's in-lane sort). Absent → cards render exactly as before.
  attrsOf?: (item: Item) => string,
): string {
  const card = (p: Item) =>
    attrsOf ? `<div class="cardw"${attrsOf(p)}>${cardLink(p, ctx)}</div>` : cardLink(p, ctx);
  const cols = lanes
    .map((lane) => {
      // Oldest-activity-first inside every lane: attention debt surfaces at the
      // top instead of hiding under fresher cards. NaN (no history) sinks last.
      const inLane = projects
        .filter((p) => keyOf(p) === lane.key)
        .sort((a, b) => (updatedAtOf(a) || Infinity) - (updatedAtOf(b) || Infinity));
      const body = inLane.length ? inLane.map(card).join("") : `<div class="empty">—</div>`;
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

export interface BoardFilter {
  domain: string;
  pipeline: string;
  q: string;
}
export interface BoardOpts {
  filter?: BoardFilter;
  archivedCount?: number;
  now?: number; // test override for age rendering
}

/** The board filter bar: plain GET form → server-side filtering, no client JS.
 *  Selects auto-submit; a Clear link appears whenever a filter is active. */
function filterBar(filter: BoardFilter, profiles: ResolvedPipeline[], domains: DomainRegistry): string {
  const active = filter.domain || filter.pipeline || filter.q;
  const domOpts = [`<option value="">domain: all</option>`, ...[...domains.domains, domains.fallback].map(
    (d) => `<option value="${esc(d.key)}"${d.key === filter.domain ? " selected" : ""}>${esc(d.label)}</option>`,
  )].join("");
  const pipeOpts = [`<option value="">pipeline: all</option>`, ...profiles.map(
    (p) => `<option value="${esc(p.pipeline)}"${p.pipeline === filter.pipeline ? " selected" : ""}>${esc(p.label)}</option>`,
  )].join("");
  return `<form class="filterbar" method="get" action="/">
  <select name="domain" onchange="this.form.submit()">${domOpts}</select>
  <select name="pipeline" onchange="this.form.submit()">${pipeOpts}</select>
  <input type="text" name="q" value="${esc(filter.q)}" placeholder="filter by text…">
  <button type="submit">filter</button>
  ${active ? `<a class="kv" href="/">✕ clear</a>` : ""}
</form>`;
}

/** Board: one page, attention-first (the assembly-line view, reordered by what
 *  needs the human). Intake + filter bar on top, then:
 *   1. **Needs You** — parked + failed projects, full width. The reason the
 *      page exists; never buried mid-scroll.
 *   2. **Active** — pending/running projects (the machine's side of the desk).
 *   3. **Hopper** — untriaged ideas in maturation-stage lanes.
 *   4. **Recently done** — passed items still inside the archive-grace window,
 *      folded shut; archived items live on /finished, linked by count.
 */
export function renderBoard(
  ideas: Item[],
  projects: Item[],
  profiles: ResolvedPipeline[],
  enabled: ResolvedPipeline[] = [],
  domains: DomainRegistry = emptyRegistry,
  opts: BoardOpts = {},
): string {
  const filter = opts.filter ?? { domain: "", pipeline: "", q: "" };
  const ctx: CardCtx = { domains, profiles, enabled, back: "/", now: opts.now };
  const byAge = (a: Item, b: Item) => (updatedAtOf(a) || Infinity) - (updatedAtOf(b) || Infinity);

  const needsYou = projects.filter((p) => p.state === "parked" || p.state === "failed").sort(byAge);
  const activeItems = projects.filter((p) => p.state === "pending" || p.state === "running");
  const done = projects.filter((p) => p.state === "passed").sort((a, b) => byAge(b, a));

  const needsYouSection = `
  <h2 class="secthdr">Decide now <span class="count">${needsYou.length}</span> <span class="kv" style="font-weight:400">each card names the blocked decision</span></h2>
  ${needsYou.length ? `<div class="grid" style="padding:0">${needsYou.map((p) => cardLink(p, ctx)).join("")}</div>` : '<div class="empty" style="padding:10px">nothing needs you — the machine is either working or waiting for ideas</div>'}`;

  const activeSection = `
  <h2 class="secthdr">In motion <span class="count">${activeItems.length}</span> <span class="kv" style="font-weight:400">the machine is handling these</span></h2>
  ${activeItems.length
    ? laneBoard(activeItems, ctx, [{ key: "pending", label: "In Pipeline" }, { key: "running", label: "Running" }], statusOf)
    : '<div class="empty" style="padding:10px">no projects in flight — promote a Ready idea below</div>'}`;

  const hopperSection = `
  <h2 class="secthdr">Hopper — ideas <span class="count">${ideas.length}</span> <span class="kv" style="font-weight:400">capture → shape → promote</span></h2>
  ${ideas.length
    ? laneBoard(ideas, ctx, HOPPER_STAGES, stageOf)
    : '<div class="empty" style="padding:10px">no ideas waiting — capture one above</div>'}`;

  const archivedNote = (opts.archivedCount ?? 0) > 0
    ? ` · <a href="/finished">${opts.archivedCount} archived</a>`
    : "";
  const doneSection = done.length || archivedNote
    ? `<details class="donefold"><summary class="secthdr">Recently done <span class="count">${done.length}</span> <span class="kv" style="font-weight:400">auto-archives to <a href="/finished">Finished</a> after the grace window${archivedNote}</span></summary>
       ${done.length ? `<div class="grid" style="padding:0">${done.map((p) => cardLink(p, ctx)).join("")}</div>` : ""}</details>`
    : "";

  const body = `
<form class="intake" method="post" action="/intake">
  <input type="text" name="text" placeholder="Capture an idea — it lands in the Hopper (and the brain backlog); shape it, then promote it when Ready…" required autofocus>
  <button type="submit">→ hopper</button>
</form>
${filterBar(filter, profiles, domains)}
<main class="exec-page">
  ${executiveHero(
    needsYou.length ? `${needsYou.length} decision${needsYou.length === 1 ? "" : "s"} need${needsYou.length === 1 ? "s" : ""} you` : "Nothing needs your decision",
    needsYou.length ? "Resolve the cards below first. Work already moving and unshaped ideas are separated so they do not compete for attention." : "Refinery can keep moving without you. Active work and new ideas are available below when you want context.",
    `${activeItems.length} project${activeItems.length === 1 ? "" : "s"} in motion · ${ideas.length} idea${ideas.length === 1 ? "" : "s"}`,
  )}
  ${needsYouSection}
  <details class="exec-fold"><summary>In motion <span class="count">${activeItems.length}</span></summary>${activeSection}</details>
  <details class="exec-fold"><summary>Ideas waiting to be shaped <span class="count">${ideas.length}</span></summary>${hopperSection}</details>
  ${doneSection}
</main>`;
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
  const ready = nightly.filter((i) => ((i.payload as { queuedCount?: number })?.queuedCount ?? 0) > 0);
  const decisions = nightly.filter((i) => i.state === "parked" || i.state === "failed").filter((i) => !ready.includes(i));
  const waiting = nightly.filter((i) => !ready.includes(i) && !decisions.includes(i));
  const body = `
<form class="intake" method="post" action="/nightly/config">
  <label class="kv">Max cards per night:</label>
  <input type="number" name="maxPerNight" min="0" value="${maxPerNight}" style="width:90px">
  <button type="submit">save</button>
  <span class="kv">safety cap for the 01:30 run</span>
</form>
<main class="exec-page">
  ${executiveHero(
    decisions.length ? `${decisions.length} need${decisions.length === 1 ? "s" : ""} a decision before tonight` : `${ready.length} project${ready.length === 1 ? "" : "s"} ready for tonight`,
    decisions.length ? "Clear the exceptions below. Queued work can run unattended after that." : ready.length ? "The overnight queue is ready. No intervention is required unless you want to change priority or run something now." : "Nothing is queued for the overnight run.",
    `${ready.length} ready · cap ${maxPerNight}`,
  )}
  <section class="exec-section"><h2>Decide before tonight <span class="count">${decisions.length}</span></h2>${decisions.length ? `<div class="grid" style="padding:0">${decisions.map((i) => cardLink(i, ctx)).join("")}</div>` : '<div class="empty">nothing blocking tonight</div>'}</section>
  <section class="exec-section"><h2>Ready for tonight <span class="count">${ready.length}</span></h2>${ready.length ? `<div class="grid" style="padding:0">${ready.map((i) => cardLink(i, ctx)).join("")}</div>` : '<div class="empty">nothing queued</div>'}</section>
  <details class="exec-fold"><summary>Not queued <span class="count">${waiting.length}</span></summary>${waiting.length ? `<div class="grid" style="padding:10px 0 0">${waiting.map((i) => cardLink(i, ctx)).join("")}</div>` : '<div class="empty">nothing waiting</div>'}</details>
</main>`;
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
    // (payload.verdicts is no longer read directly here — judgmentsFor folds
    // events first and falls back to that slot itself.)
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

    // Earlier verdicts for a step, newest first — the point of versioning
    // judgments. One producer: gates AND the executor both render through it,
    // because both now append judgment events (runner.ts, run-once, run-native).
    const priorTrail = (trail: ReturnType<typeof judgmentsFor>, label: string): string =>
      trail.length > 1
        ? `<div class="kv" style="margin-top:8px">earlier verdicts for this ${label}:</div>` +
          trail
            .slice(0, -1)
            .reverse()
            .map(
              (j) =>
                `<div class="hist">v${j.version}${j.at ? ` · ${esc(j.at)}` : ""} · ${esc(String(j.decision ?? "?"))}${j.verdict ? ` — ${esc(j.verdict)}` : ""}</div>`,
            )
            .join("")
        : "";
    // "v2 of 2" only reads right while no judgment has been compacted away.
    // Past that, version and count diverge, so show the count honestly.
    const trailCount = (trail: ReturnType<typeof judgmentsFor>): string => {
      if (trail.length <= 1) return "";
      const current = trail[trail.length - 1]!;
      return current.version === trail.length
        ? `<div class="kv">verdict v${current.version} of ${trail.length}</div>`
        : `<div class="kv">verdict v${current.version} · ${trail.length} kept (older ones compacted)</div>`;
    };

    // Gate nodes — each gate's verdict trail, events-first with the
    // payload.verdicts[step] fallback (judgmentsFor). Showing the whole trail
    // rather than only the newest is the point of versioning judgments: a gate
    // that parked then passed on re-run now shows both, instead of the second
    // verdict silently erasing the first.
    const gateNodes = pipeline.gates
      .map((g) => {
        const trail = judgmentsFor(item, g);
        const st = states.get(g) ?? "pending";
        const current = trail.length ? trail[trail.length - 1]! : null;
        const body = current
          ? `${current.decision != null ? `<div><b>decision:</b> ${esc(String(current.decision))}</div>` : ""}${current.verdict != null ? `<div><b>reason:</b> ${esc(String(current.verdict))}</div>` : ""}${trailCount(trail)}${prettyOutput(current.output)}${priorTrail(trail, "gate")}`
          : st === "skipped"
            ? `<div class="kv">skipped — this gate did not apply to the item</div>`
            : `<div class="kv">no verdict recorded for this step</div>`;
        return node(g, st, body);
      })
      .join(arrow);

    // Executor node — payload.executorResult for the rich current-state fields
    // (branch/pushed/pristine), PLUS the executor's own judgment trail. Both
    // executor finalizers append judgments; without this the trail was written
    // and read by nothing, so a re-run's earlier result stayed invisible.
    const branch = typeof execResult.branch === "string" ? execResult.branch : "";
    const execTrail = executorId ? judgmentsFor(item, executorId) : [];
    const execBody = Object.keys(execResult).length
      ? `${execResult.outcome != null ? `<div><b>outcome:</b> ${esc(String(execResult.outcome))}</div>` : ""}${execResult.verdict != null ? `<div><b>verdict:</b> ${esc(String(execResult.verdict))}</div>` : ""}${branch ? `<div><b>branch:</b> ${esc(branch)}</div>` : ""}${"pushed" in execResult ? `<div><b>pushed:</b> ${String(execResult.pushed)}</div>` : ""}${"pristine" in execResult ? `<div><b>pristine:</b> ${String(execResult.pristine)}</div>` : ""}${"reportPresent" in execResult ? `<div><b>report:</b> ${String(execResult.reportPresent)}</div>` : ""}${execResult.detail != null ? `<div><b>detail:</b> ${esc(String(execResult.detail))}</div>` : ""}${trailCount(execTrail)}${prettyOutput(execResult.output)}${priorTrail(execTrail, "executor")}`
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
    // concrete decisions the human must make) in its judgment output. Read
    // events-first via judgmentsFor, which falls back to the legacy
    // payload.verdicts[step] slot for items written before the event log.
    const pv = currentJudgment(item, item.step ?? "");
    const rawAsks = obj(pv?.output).asks;
    const asks = Array.isArray(rawAsks) ? rawAsks.filter((a) => typeof a === "string") as string[] : [];
    const askList = asks.length
      ? `<div class="asks"><div class="askhdr">To unblock, decide:</div><ol>${asks.map((a) => `<li>${esc(a)}</li>`).join("")}</ol></div>`
      : `<div class="kv" style="margin-bottom:8px">This step needs a human call — answer below to re-arm and continue, or rewind to revisit an earlier step. (No structured asks recorded${pv?.output ? "" : "; this item ran before asks were captured — re-run to get them"}.)</div>`;
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

  const detailHeadline = item.state === "parked" || item.state === "failed"
    ? "A decision is blocking this work"
    : item.state === "passed" ? "This work is complete" : item.state === "running" ? "Refinery is working on this" : "This work is ready to move";
  const detailMeaning = item.parkedReason || (input ? String(input) : `${titleOf(item)} is currently ${item.state}.`);
  const body = `<main class="exec-page" style="max-width:820px">
  <a href="/" class="kv">← board</a>
  ${executiveHero(detailHeadline, detailMeaning, `${item.state} · ${item.step ?? item.stage ?? "—"}`)}
  <h2><span class="swatch" style="background:${esc(color)}"></span> ${esc(titleOf(item))}</h2>
  <div class="kv">${isIdea ? "idea (untriaged)" : `project · ${esc(item.pipeline)}`}${goal ? ` · goal: <b>${esc(goal)}</b>` : ""} · step <b>${esc(item.step ?? item.stage ?? "—")}</b> · ${esc(item.state)} ${isNightly ? "· 🌙 nightly" : ""}</div>
  ${item.parkedReason ? `<div class="reason">${esc(item.parkedReason)}</div>` : ""}
  ${input ? `<div class="md"><p><em>${esc(input)}</em></p></div>` : ""}

  ${actions}

  <details class="exec-fold"><summary>Technical evidence</summary>
    ${cardBody ? `<h2>Card</h2><div class="md">${mdToHtml(cardBody)}</div>` : ""}
    ${pipelineNodes}
    <h2>Payload</h2><pre>${esc(JSON.stringify(item.payload, null, 2))}</pre>
    <h2>Timeline</h2>${timeline}
  </details>
</main>`;
  return layout("", body);
}

/** Gauntlet page: one component over a GauntletView shim (gauntlet-views.ts).
 *  Investigations as a status-lane kanban (cards → tabbed detail). Lanes are
 *  the distinct values of the view's lane field (data-driven), so a new lane
 *  value needs no renderer edit — and a new GAUNTLET needs only a new shim. */
export function renderGauntletBoard(
  view: GauntletView,
  items: Item[],
  maxPerRun: number,
  profiles: ResolvedPipeline[],
  domains: DomainRegistry = emptyRegistry,
  /** Extra panel above the run list (dx1: the live cases table). */
  topPanel?: string,
): string {
  const laneOf = (item: Item): string => {
    const p = item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};
    const v = p[view.laneField];
    return typeof v === "string" && v ? v : view.laneFallback;
  };
  const lanes = [...new Set(items.map(laneOf))].sort().map((s) => ({ key: s, label: s }));
  // Gauntlet cards are read-only mirrors (no inline controls); run-now lives on detail.
  const ctx: CardCtx = { domains, profiles, enabled: [], back: `/${view.key}` };
  // Card wrappers carry the run date so the enhancer can sort within lanes
  // (lanes themselves ARE the verdict axis; the lane toggles are the verdict
  // filter).
  const board = laneBoard(items, ctx, lanes, laneOf, (i) => ` data-date="${esc(view.sortDate?.(i) ?? "")}"`);
  const capForm = (cls: string) => `
<form class="${cls}" method="post" action="/${view.key}/config">
  <label class="kv">${esc(view.capLabel)}</label>
  <input type="number" name="maxPerNight" min="0" value="${maxPerRun}" style="width:90px">
  <button type="submit">save</button>
  <span class="kv">${items.length} investigations · ${esc(view.capNote)}</span>
</form>`;
  const kanban = `<div class="wrap"${items.length ? ' data-enhance="lanes"' : ""}>${items.length ? board : `<div class="empty" style="padding:24px">${esc(view.emptyText)}</div>`}</div>`;
  const pendingCount = items.filter((i) => laneOf(i) === view.laneFallback).length;
  const unresolvedItems = items.filter((i) => laneOf(i) === view.laneFallback);
  const resolvedItems = items.filter((i) => laneOf(i) !== view.laneFallback);
  const boardFor = (subset: Item[]): string => subset.length
    ? `<div class="wrap" data-enhance="lanes">${laneBoard(subset, ctx, lanes, laneOf, (i) => ` data-date="${esc(view.sortDate?.(i) ?? "")}"`)}</div>`
    : '<div class="empty">nothing here</div>';
  const summary = executiveHero(
    pendingCount ? `${pendingCount} investigation${pendingCount === 1 ? "" : "s"} still unresolved` : "Nothing needs your decision",
    pendingCount ? "Review unresolved investigations first. Completed reports remain available as history." : "Completed investigations are reference material. Start or repeat a run only when the live situation warrants it.",
    `${items.length} investigation record${items.length === 1 ? "" : "s"}`,
  );

  if (view.section) {
    // Sectioned layout (dx1): shared header + tab bar, cases panel on top,
    // finished runs below, cap control demoted to the ⚙ settings corner.
    const body = `${sectionHeader(view.section, "runs", `<details class="cfg"><summary title="settings">⚙</summary>${capForm("intake cfgform")}</details>`)}
<main class="exec-page">${summary}<section class="exec-section"><h2>What needs attention</h2>${topPanel ?? '<div class="empty">no live case feed</div>'}</section>
<details class="exec-fold"><summary>Completed investigations — history <span class="count">${items.length}</span></summary><div class="secblock"><h3 class="sechead">Completed investigations</h3>
${items.length ? "" : `<div class="kv" style="padding:0 18px">${esc(view.emptyText)} — force one from the cases table above.</div>`}
${kanban}</div></details></main>`;
    return layout(view.key, body);
  }

  const body = `<main class="exec-page">${summary}
<section class="exec-section"><h2>What needs attention</h2>${boardFor(unresolvedItems)}</section>
<details class="exec-fold"><summary>Completed investigations — history <span class="count">${resolvedItems.length}</span></summary>${boardFor(resolvedItems)}</details>
<details class="exec-fold"><summary>Run settings</summary>${capForm("intake")}</details>
</main>`;
  return layout(view.key, body);
}

/** Shared section chrome for multi-tab views (dx1): one header, one tab bar,
 * both pages identical — the tab carries the page identity. */
function sectionHeader(
  section: NonNullable<GauntletView["section"]>,
  activeKey: string,
  corner = "",
): string {
  const tabs = section.tabs
    .map((t) => `<a href="${esc(t.href)}" class="${t.key === activeKey ? "active" : ""}">${esc(t.label)}</a>`)
    .join("");
  return `<div class="sechdr">
  <h2>${esc(section.title)}</h2>
  <nav class="subtabs">${tabs}</nav>
  ${corner}
</div>`;
}

/** Gauntlet detail: the SR2 modal layout — header (category / subject /
 *  question) + file tabs + a composed Details tab (CSS-only). The first tab
 *  (the report) is the default so it's the thing you land on. */
export function renderGauntletDetail(
  view: GauntletView,
  item: Item,
  bundle: GauntletRunBundle,
): string {
  const head = view.headerOf(item);

  // Force a fresh investigation now (<view>-gauntlet-runnow drains the spool →
  // run.sh --id). The board only writes the request.
  const runNow = view.runNow && head.runId
    ? `<form method="post" action="/${view.key}/run-now" style="margin-top:8px">
         <input type="hidden" name="${esc(view.runNow.field)}" value="${esc(head.runId)}">
         <input type="hidden" name="id" value="${esc(item.id)}">
         <button type="submit" title="${esc(view.runNow.title(head.runId))}">${esc(view.runNow.button)}</button>
         <span class="kv">${esc(view.runNow.caption)}</span>
       </form>`
    : "";

  // Per-tab + combined downloads, served by GET /<view>/export/<part>?id=…
  // (Content-Disposition attachment). Registry-driven — every gauntlet gets
  // the same buttons; compositions live in gauntlet-views.ts (one producer).
  const exportHref = (part: string) =>
    `/${view.key}/export/${encodeURIComponent(part)}?id=${encodeURIComponent(item.id)}`;
  const exportRow = `<div class="kv" style="margin-top:8px">⬇ export: ${[
    ...view.tabs.map((t) => `<a href="${exportHref(t.key)}">${esc(t.label.toLowerCase())}</a>`),
    `<a href="${exportHref("details")}">details</a>`,
    `<a href="${exportHref("all")}">all</a>`,
  ].join(" · ")}</div>`;

  const detailsMd = detailsExportMd(view, item, bundle);

  const panel = (md: string | null, empty: string) =>
    `<div class="md">${md ? mdToHtml(md) : `<p class="kv">${empty}</p>`}</div>`;

  const tabs = [...view.tabs, { key: "details", label: "Details", files: [], empty: "" }];
  const radios = tabs
    .map((t, i) => `<input type="radio" name="srt" id="srt-${esc(t.key)}"${i === 0 ? " checked" : ""}>`)
    .join("\n  ");
  const labels = tabs.map((t) => `<label for="srt-${esc(t.key)}">${esc(t.label)}</label>`).join("\n    ");
  const panels = tabs
    .map((t) =>
      t.key === "details"
        ? `<div class="panel" id="srp-details">${panel(detailsMd, "")}</div>`
        : `<div class="panel" id="srp-${esc(t.key)}">${panel(tabMd(t, bundle), t.empty)}</div>`,
    )
    .join("\n  ");

  const recommendation = head.cat === view.laneFallback
    ? `Review the report, then use ${view.runNow?.button ?? "the run control"} if the evidence is stale or incomplete.`
    : "Use the report as the decision record. Re-run only if the underlying case has materially changed.";
  const body = `<main class="exec-page" style="max-width:900px">
  ${executiveHero("What happened", `${head.title}: ${head.question || "an investigation record is available"}`, head.cat)}
  <section class="decision-note"><b>Recommended action:</b> ${esc(recommendation)}</section>
  <div class="srtabs">
  ${radios}
  <div class="srhead">
    <a href="/${view.key}" class="kv">← ${esc(view.label)}</a>
    <div class="cat">${esc(head.cat)}</div>
    <h2>${esc(head.title)}</h2>
    <div class="q">${esc(head.question)}</div>
    ${runNow}
    ${exportRow}
  </div>
  <div class="srtabbar">
    ${labels}
  </div>
  ${panels}
</div></main>`;
  return layout(view.key, body);
}

// ── /dx1/fleet — cohort-health table over the daily fleet snapshot ──────────
// Bespoke-but-shimmed (see dx1-fleet.ts header): dx1-specific analytics, no
// second consumer yet, so it does not stretch the GauntletView registry.
// Visual model: the datax dx1-health Agents tab (dense table + family badges),
// re-expressed in the board's server-rendered idiom.

function fleetPct(v: number | undefined | null): string {
  return typeof v === "number" ? `${v.toFixed(1)}%` : "—";
}
function fleetNum(v: number | undefined | null): string {
  return typeof v === "number" ? String(v) : "—";
}

function fleetDeltaHtml(delta: number | null): string {
  if (delta === null || Math.abs(delta) < 0.05) return "";
  const up = delta > 0;
  return ` <span class="${up ? "up" : "down"}" title="clean% vs previous snapshot">${up ? "↑" : "↓"}${Math.abs(delta).toFixed(1)}</span>`;
}

function fleetFamiliesHtml(fams: Record<string, number> | null | undefined): string {
  if (!fams || Object.keys(fams).length === 0) return `<span class="kv">—</span>`;
  return Object.entries(fams)
    .sort((a, b) => b[1] - a[1])
    .map(([f, n]) => `<span class="fam" style="border-color:${fleetFamilyColor(f)};color:${fleetFamilyColor(f)}">${esc(f)}×${n}</span>`)
    .join("");
}

/** Datax dx1-health executions drill for an agent — the same link vocabulary
 * the gauntlet reports use. */
const DX1_HEALTH_AGENT_URL = "https://datax.to/x/admin/dx1-health?tab=executions&agent=";

/** The fleet page's copy of the shared DX1 section header (active: fleet). */
function dx1FleetHeader(): string {
  const section = gauntletViewByKey("dx1")?.section;
  return section ? sectionHeader(section, "fleet") : "";
}

/** Live-cases panel — the Investigations tab's "what do I do here": every
 * dx1Case with the runner's own queue/skip verdict in plain words and a
 * force-investigate button (run-now spool; --id ignores qualification).
 * Cases whose fingerprint has a completed run link to the run detail. */
export function renderDx1CasesPanel(
  casesFile: Dx1CasesFile | null,
  runIdByFingerprint: Map<string, string>,
  now: string,
): string {
  if (!casesFile || casesFile.cases.length === 0) {
    return `<div class="secblock"><h3 class="sechead">Live cases</h3>
<div class="kv" style="padding:0 18px">no case feed yet — fetch-cases writes state/cases.json on every gauntlet tick</div></div>`;
  }
  const ageMin = casesFile.generatedAt
    ? Math.max(0, Math.round((new Date(now).getTime() - new Date(casesFile.generatedAt).getTime()) / 60_000))
    : null;
  const sorted = [...casesFile.cases].sort((a, b) => {
    // Open + queued cases surface first, then by peak failures.
    const w = (c: DxCase) => (c.status === "queue" ? 0 : c.state === "open" ? 1 : 2);
    return w(a) - w(b) || (b.peakWindowFailures ?? 0) - (a.peakWindowFailures ?? 0);
  });
  type DxCase = Dx1CasesFile["cases"][number];
  const rows = sorted.map((c) => {
    const runItemId = runIdByFingerprint.get(c.fingerprint);
    const who = `<b>${esc(c.orgName || (c.orgId ? `JT ${c.orgId}` : "(org unknown)"))}</b> — ${
      c.agentId
        ? `<a href="${DX1_HEALTH_AGENT_URL}${encodeURIComponent(c.agentId)}" target="_blank" rel="noopener" title="dx1-health executions for this agent">${esc(c.agentName || c.agentId)}</a>`
        : esc(c.agentName ?? "unknown")
    }<div class="kv">${esc(c.fingerprint)}</div>`;
    const runLink = runItemId
      ? `<a href="/project/${encodeURIComponent(runItemId)}">report →</a>`
      : c.investigated
        ? `<span class="kv" title="ledger says investigated, but the run dir is not on this host">investigated</span>`
        : `<span class="kv">—</span>`;
    return `<tr>
      <td>${who}</td>
      <td><span class="fam" style="border-color:${fleetFamilyColor(c.family ?? "")};color:${fleetFamilyColor(c.family ?? "")}">${esc(c.family ?? "?")}</span></td>
      <td>${esc(c.state ?? "?")}</td>
      <td class="n">${c.peakWindowFailures ?? "—"}</td>
      <td>${c.lastSeen ? esc(c.lastSeen.slice(0, 10)) : "—"}</td>
      <td>${esc(caseStatusLabel(c))}</td>
      <td>${runLink}</td>
      <td><form method="post" action="/dx1/run-now"><input type="hidden" name="caseId" value="${esc(c.fingerprint)}"><button type="submit" title="force an investigation of this case now (ignores the queue rules)">▶ investigate</button></form></td>
    </tr>`;
  }).join("\n    ");
  return `<div class="secblock">
  <h3 class="sechead">Live cases <span class="kv">${casesFile.cases.length} tracked${ageMin !== null ? ` · feed ${ageMin < 60 ? `${ageMin}m` : `${Math.round(ageMin / 60)}h`} old` : ""} · ▶ forces a run even when skipped</span></h3>
  <table data-enhance="table" class="cases">
    <tr><th>Case</th><th>Family</th><th>State</th><th class="n">Peak fails</th><th>Last seen</th><th>Status</th><th>Run</th><th></th></tr>
    ${rows}
  </table>
</div>`;
}

/** Member rows as REAL table rows aligned under the cohort columns (col 1 =
 * client + agent, then Tasks / Clean%pooled / — / needs-help+err / runtime
 * med / stalls / — / burn). Assigned members AND diverged forks (⑂) both
 * render — actives by tasks desc first, then quiet, then legacy. Each row
 * shares the cohort's data-group so sorting/filtering travel whole; the
 * enhancer collapses them behind the ▾ toggle (no-JS = expanded = complete). */
function fleetMemberRows(
  t: FleetTemplate,
  agentRuns: Map<string, { run: string; verdict?: string }>,
): string {
  const isLegacy = (m: FleetMember) => !("org" in m) && !("stats" in m);
  // ONE expansion level: assigned members first (actives by tasks desc, then
  // quiet/legacy), then a "diverged forks" divider row carrying the
  // aggregate, then the ⑂ fork rows (same ordering). No nested toggles —
  // the double-caret pair toggled one shared state and the second click
  // collapsed what the first opened ("everything disappears").
  const byActivity = (list: FleetMember[], fork: boolean) =>
    list
      .map((m, i) => ({ m, fork, i, tasks: !isLegacy(m) && m.stats ? m.stats.tasks : -1 }))
      .sort((a, b) => b.tasks - a.tasks || a.i - b.i);
  const sorted = byActivity(t.members ?? [], false);
  const forks = byActivity(t.divergedMembers ?? [], true);

  const dash = `<span class="kv">—</span>`;
  const row = ({ m, fork }: { m: FleetMember; fork: boolean }): string => {
    const inv = m.id ? agentRuns.get(m.id) : undefined;
    const nameLink = m.id
      ? `<a href="${DX1_HEALTH_AGENT_URL}${encodeURIComponent(m.id)}" target="_blank" rel="noopener" title="dx1-health executions for this agent">${esc(m.name ?? "?")}</a>`
      : esc(m.name ?? "?");
    const invLink = inv
      ? ` · <a href="/project/${encodeURIComponent(`dx1:${inv.run}`)}" title="gauntlet investigation${inv.verdict ? ` — ${esc(inv.verdict)}` : ""}">investigation →</a>`
      : "";
    const suffix = `<div class="kv">${esc(m.id ?? "")} · ratio ${typeof m.ratio === "number" ? m.ratio.toFixed(2) : "?"}${invLink}</div>`;
    const flag = fork ? "⑂ " : "";

    if (isLegacy(m)) {
      // Pre-2026-08-17 snapshot: no org/stats — name + suffix, numerics em-dash.
      return `<tr class="mem" data-group="${esc(t.rootId)}"><td>${flag}${nameLink}${suffix}</td>${`<td class="n">${dash}</td>`.repeat(6)}<td>${dash}</td><td class="n">${dash}</td></tr>`;
    }
    const org = `<b>${esc(m.org ?? "(org unknown)")}</b>`;
    const s = m.stats;
    if (!s) {
      return `<tr class="mem quiet" data-group="${esc(t.rootId)}"><td>${flag}${org} — ${nameLink} <span class="kv">no runs in window</span>${suffix}</td>${`<td class="n">${dash}</td>`.repeat(6)}<td>${dash}</td><td class="n">${dash}</td></tr>`;
    }
    return `<tr class="mem" data-group="${esc(t.rootId)}">
      <td>${flag}${org} — ${nameLink}${suffix}</td>
      <td class="n">${dash}</td>
      <td class="n">${s.tasks}</td>
      <td class="n">${typeof s.cleanPct === "number" ? `${s.cleanPct.toFixed(1)}%` : "—"}</td>
      <td class="n" title="${s.needsHelp} needs-help + ${s.errors} errors">${s.needsHelp}+${s.errors}</td>
      <td class="n">${typeof s.runtimeMedianMin === "number" ? `${s.runtimeMedianMin.toFixed(1)}m` : "—"}</td>
      <td class="n">${s.stalls}</td>
      <td>${dash}</td>
      <td class="n">${typeof s.burnMaxM === "number" ? `≤${s.burnMaxM.toFixed(2)}M` : "—"}</td>
    </tr>`;
  };

  // Divider row: the diverged aggregate leads its forks inside the ONE
  // expansion (it is itself a .mem row, so it collapses with the rest).
  const divider = forks.length
    ? `<tr class="mem divider" data-group="${esc(t.rootId)}">
      <td>⑂ diverged forks (${forks.length})</td>
      <td class="n">${t.divergedRates ? t.divergedRates.agents : forks.length}</td>${t.divergedRates ? fleetRateCells(t.divergedRates) : `${`<td class="n">${dash}</td>`.repeat(5)}<td>${dash}</td><td class="n">${dash}</td>`}
    </tr>`
    : "";
  return [...sorted.map(row), divider, ...forks.map(row)].filter(Boolean).join("\n    ");
}

function fleetRateCells(r: FleetRates, deltaHtml = ""): string {
  const rt = r.runtime;
  const burn = r.tokenBurnUpperBound336h;
  // ONE Clean % column (pooled excl-quota — the honest headline); the
  // per-agent median lives in the tooltip so the table stops asking the
  // reader to know two clean numbers apart.
  const medianTip = typeof r.cleanMedianPct === "number"
    ? ` title="per-agent median: ${r.cleanMedianPct.toFixed(1)}% — a big gap means a few agents drag the pool"`
    : "";
  return `
      <td class="n">${fleetNum(r.tasks)}</td>
      <td class="n"${medianTip}>${fleetPct(r.cleanPooledExclQuotaPct)}${deltaHtml}</td>
      <td class="n">${fleetPct(r.needsHelpErrExclQuotaPct)}</td>
      <td class="n">${rt ? `${rt.medianMin.toFixed(1)} / ${rt.p90Min.toFixed(1)}` : "—"}</td>
      <td class="n" title="stall events (tasks with a stall)">${fleetNum(r.stallEvents)}${typeof r.tasksWithStall === "number" ? ` <span class="kv">(${r.tasksWithStall})</span>` : ""}</td>
      <td>${fleetFamiliesHtml(r.engineFamilies7d)}</td>
      <td class="n" title="UPPER BOUND — subscription-cumulative deltas, concurrent tasks bleed in">${burn ? `≤${burn.medianM.toFixed(2)}M / ≤${burn.maxM.toFixed(2)}M <span class="kv">(n=${burn.tasksMeasured})</span>` : "—"}</td>`;
}

/** Fleet cohort-health table: one row per template cohort (tasks desc), an
 * indented diverged-forks sub-row where present, CSS-only member expansion,
 * clean%% trend arrows vs the previous snapshot, and the method notes
 * rendered verbatim — the honesty block is part of the page, not decoration. */
export function renderDx1Fleet(
  latest: FleetSnapshot | null,
  previous: FleetSnapshot | null,
  now: string,
  agentRuns: Map<string, { run: string; verdict?: string }> = new Map(),
): string {
  if (!latest) {
    const body = `${dx1FleetHeader()}<div class="fleet">
<div class="empty" style="padding:24px">no fleet snapshots yet — dx1_gauntlet writes state/fleet-history/YYYY-MM-DD.json daily</div>
</div>`;
    return layout("dx1", body);
  }

  const ageDays = latest.generatedAt
    ? Math.max(0, Math.floor((new Date(now).getTime() - new Date(latest.generatedAt).getTime()) / 86_400_000))
    : null;
  const cohorts = [...latest.templates].sort((a, b) => (b.rates.tasks ?? 0) - (a.rates.tasks ?? 0));
  const measured = cohorts.filter((c) => typeof c.rates.cleanPooledExclQuotaPct === "number" && (c.rates.tasks ?? 0) > 0);
  const taskTotal = measured.reduce((n, c) => n + (c.rates.tasks ?? 0), 0);
  const clean = taskTotal
    ? measured.reduce((n, c) => n + (c.rates.cleanPooledExclQuotaPct ?? 0) * (c.rates.tasks ?? 0), 0) / taskTotal
    : null;
  const weakest = [...measured].sort((a, b) => (a.rates.cleanPooledExclQuotaPct ?? 101) - (b.rates.cleanPooledExclQuotaPct ?? 101))[0];
  const unassigned = latest.fleet?.unassignedCount ?? 0;
  const recommendation = weakest && (weakest.rates.cleanPooledExclQuotaPct ?? 100) < 90
    ? `Inspect ${weakest.name} first; it has the lowest measured clean rate (${fleetPct(weakest.rates.cleanPooledExclQuotaPct)}).`
    : unassigned > 0
      ? `Cohort outcomes look stable; review the ${unassigned} unassigned agents when capacity allows.`
      : "No fleet intervention is indicated by this snapshot.";

  const rows = cohorts
    .map((t) => {
      const untouched = t.cohortSize - (t.divergedForks ?? 0);
      const memberCount = (t.members?.length ?? 0) + (t.divergedMembers?.length ?? 0);
      // ONE caret per cohort (the caret pair toggled a single shared state,
      // so the second caret collapsed what the first opened — Eric's
      // "everything disappears"). ▾ server-rendered EXPANDED (no-JS pages are
      // complete); the enhancer collapses member rows and wires the toggle.
      const toggle = memberCount
        ? `<span class="mtoggle" data-group="${esc(t.rootId)}" title="show/hide the ${memberCount} member agents (⑂ forks grouped at the end)">▾</span> `
        : "";
      const nameCell = `${toggle}${esc(t.name)}
        <div class="kv">${esc(t.author ?? "")}${typeof t.downloads === "number" ? ` · ${t.downloads}↓` : ""}${memberCount ? ` · ${memberCount} members` : ""}</div>`;
      const main = `<tr data-group="${esc(t.rootId)}">
      <td>${nameCell}</td>
      <td class="n" title="${untouched} untouched (${t.byteIdentical ?? 0} byte-identical) / ${t.divergedForks ?? 0} diverged">${t.cohortSize}${(t.divergedForks ?? 0) > 0 ? ` <span class="kv">(${untouched}/${t.divergedForks}⑂)</span>` : ""}</td>${fleetRateCells(t.rates, fleetDeltaHtml(cohortCleanDelta(t, previous)))}
    </tr>`;
      return main + (memberCount ? `\n    ${fleetMemberRows(t, agentRuns)}` : "");
    })
    .join("\n    ");

  const m = latest.method ?? {};
  const methodLines = ["note", "runtime", "tokenBurn", "engineFamilies", "similarity"]
    .filter((k) => typeof m[k] === "string")
    .map((k) => `<p><b>${esc(k)}:</b> ${esc(String(m[k]))}</p>`)
    .join("\n");
  const thresholds = [
    typeof m.assignThreshold === "number" ? `assign ≥ ${m.assignThreshold}` : "",
    typeof m.divergedFloor === "number" ? `diverged ≥ ${m.divergedFloor}` : "",
  ].filter(Boolean).join(" · ");

  const body = `${dx1FleetHeader()}<main class="exec-page">
  ${executiveHero("Fleet health at a glance", clean === null ? "No task outcomes are available in the latest snapshot." : `${fleetPct(clean)} of measured tasks completed cleanly across the cohort fleet.`, `${latest.fleet?.productionAgents ?? "?"} agents · ${cohorts.length} cohorts`)}
  <section class="decision-note"><b>What I recommend:</b> ${esc(recommendation)}</section>
  <details class="exec-fold"><summary>Full cohort data <span class="count">${cohorts.length}</span></summary><div class="fleet" style="padding:10px 0 0">
  <div class="meta">snapshot ${esc(latest.date)}${ageDays !== null ? ` (${ageDays === 0 ? "today" : `${ageDays}d old`})` : ""} · ${latest.windowDays ?? "?"}d window · ${latest.fleet?.productionAgents ?? "?"} production agents · ${cohorts.length} cohorts · ${latest.fleet?.unassignedCount ?? "?"} unassigned${previous ? ` · trend vs ${esc(previous.date)}` : " · no previous snapshot — no trend yet"}</div>
  <table data-enhance="table">
    <tr><th>Template cohort</th><th class="n">Agents</th><th class="n">Tasks</th><th class="n" title="pooled over the cohort's tasks, quota errors excluded; hover a value for the per-agent median">Clean %</th><th class="n">Needs-help+err %</th><th class="n">Runtime min<br><span style="font-weight:400">med / p90</span></th><th class="n">Stalls</th><th>Engine families 7d</th><th class="n">Token burn<br><span style="font-weight:400">med / max</span></th></tr>
    ${rows}
  </table>
  <div class="method">
    <p><b>Method${thresholds ? ` (${esc(thresholds)})` : ""}:</b> these are cohort <b>outcome/health rates, NOT task quality</b>.</p>
${methodLines}
  </div>
</div></details></main>`;
  return layout("dx1", body);
}

export interface SrFiles {
  gameplan: string | null; // REPORT.md (the solution)
  thread: string | null; // sr.md (the conversation)
  context: string | null; // context.md (customer pack)
}

/** SR page — the SR shim over the generic gauntlet board (parity-gated). */
export function renderSr(
  srs: Item[],
  maxPerNight: number,
  profiles: ResolvedPipeline[],
  domains: DomainRegistry = emptyRegistry,
): string {
  return renderGauntletBoard(gauntletViewByKey("sr")!, srs, maxPerNight, profiles, domains);
}

/** SR detail — the SR shim over the generic gauntlet detail (parity-gated). */
export function renderSrDetail(item: Item, files: SrFiles): string {
  return renderGauntletDetail(gauntletViewByKey("sr")!, item, {
    tabs: {
      gameplan: files.gameplan === null ? [] : [{ name: "REPORT.md", content: files.gameplan }],
      thread: files.thread === null ? [] : [{ name: "sr.md", content: files.thread }],
    },
    context: files.context,
    detail: [],
  });
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

  const nightlyHeadline = allDone ? "This project is complete" : queuedCount > 0 ? "This project is ready to run" : nextBlocked ? "A blocked step needs your decision" : "This project is not queued";
  const nightlyMeaning = allDone ? "No action is required." : queuedCount > 0 ? `The next step will run ${mode === "immediate" ? "immediately" : "in the 01:30 batch"}.` : nextBlocked ? "Force-queue only if you deliberately accept the blocked condition." : "Queue the next step or run it now.";
  const body = `<main class="exec-page" style="max-width:820px">
  <a href="/nightly" class="kv">← nightly</a>
  ${executiveHero(nightlyHeadline, nightlyMeaning, `${done}/${total} steps done`)}
  <h2><span class="swatch" style="background:${color}"></span> ${esc(titleOf(item))} <span class="badge">${mode === "immediate" ? "⚡ immediate" : "🌙 nightly"}</span></h2>
  <div class="kv">project · nightly-build · goal <b>${esc(goalId)}</b> · ${done}/${total} steps</div>
  <div class="bar"><span style="width:${pct}%"></span></div>

  <h2>Queue</h2>
  ${queueControl}

  <h2>Run now</h2>
  ${runControl || '<div class="kv">nothing to run — all steps done ✓</div>'}

  <h2>Mode</h2>
  ${modeControl}

  <details class="exec-fold"><summary>Steps and goal</summary><div class="steps">${stepRows || '<div class="empty">no steps</div>'}</div>
  ${goalBody ? `<h2>Goal</h2><div class="md">${mdToHtml(goalBody)}</div>` : ""}</details>
</main>`;
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
  archived: Item[] = [],
): string {
  const ctx: CardCtx = { domains, profiles, enabled, back: "/finished" };
  const cards = finished.map((p) => cardLink(p, ctx)).join("");
  // Archived engine items — the board's exit ramp lands here. A lane move on the
  // detail page (or the card's status select) revives one back to the board.
  const archivedSection = archived.length
    ? `<h2 class="secthdr" style="padding:0 4px">Archived items <span class="count">${archived.length}</span> <span class="kv" style="font-weight:400">passed engine items swept off the board — change status to revive</span></h2>
       <div class="grid" style="padding:0;width:100%">${archived.map((p) => cardLink(p, ctx)).join("")}</div>`
    : "";
  const body = `<main class="exec-page">
${executiveHero("Nothing needs you here", "This is completed work. Open an item only to review the record or deliberately send it back with amendments.", `${finished.length} finished · ${archived.length} archived`)}
<details class="exec-fold"><summary>Completed work <span class="count">${finished.length}</span></summary>${finished.length ? `<div class="grid" style="padding:10px 0 0">${cards}</div>` : '<div class="empty" style="padding:24px">no finished projects yet</div>'}</details>
${archivedSection ? `<details class="exec-fold"><summary>Archived engine items <span class="count">${archived.length}</span></summary>${archivedSection}</details>` : ""}
</main>`;
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

  const body = `<main class="exec-page" style="max-width:820px">
  <a href="/finished" class="kv">← finished</a>
  ${executiveHero("No action needed", "This project completed every step. Send it back only when you have a specific amendment.", `${done}/${total} steps complete`)}
  <h2><span class="swatch" style="background:${color}"></span> ${esc(titleOf(item))} <span class="badge">✓ finished</span></h2>
  <div class="kv">project · nightly-build · goal <b>${esc(goalId)}</b> · ${done}/${total} steps</div>
  <div class="bar"><span style="width:${pct}%"></span></div>

  <h2>Send back with amendments</h2>
  ${sendback}
  <details class="exec-fold"><summary>Completed steps and original goal</summary><div class="steps">${stepRows || '<div class="empty">no steps</div>'}</div>
  ${goalBody ? `<h2>Goal</h2><div class="md">${mdToHtml(goalBody)}</div>` : ""}</details>
</main>`;
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
  const body = `<main class="exec-page" style="max-width:920px">
  ${executiveHero("How Refinery works", "Use this page when a label is unfamiliar. Work enters as an idea, is routed through checks, then either asks for your decision or completes through an executor.", `${pipelines.filter((p) => p.enabled).length} active pipelines`)}
  <section class="decision-note"><b>In plain English:</b> Board shows decisions and work in motion. Overnight controls unattended work. Reviews are merge decisions. SR and DX1 are investigation workspaces. Finished is history.</section>
  <h2>Glossary</h2>
  <table style="width:100%;border-collapse:collapse" class="ref">
    <thead><tr><th style="text-align:left;padding:6px 8px;color:var(--dim)">Term</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Definition</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <details class="exec-fold"><summary>Technical pipeline catalog <span class="count">${pipelines.length}</span></summary><h2>Live pipelines</h2>
  <table style="width:100%;border-collapse:collapse" class="ref">
    <thead><tr><th style="text-align:left;padding:6px 8px;color:var(--dim)">Pipeline</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Gates (in order)</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Executor</th><th style="text-align:left;padding:6px 8px;color:var(--dim)">Enabled</th></tr></thead>
    <tbody>${plRows}</tbody>
  </table></details>
</main>`;
  return layout("reference", body);
}

// Review-only presentation rules stay scoped to this surface so unrelated
// gauntlet parity snapshots do not change when the executive view evolves.
const REVIEW_STYLE = `<style>
  .review-page{max-width:1180px;margin:0 auto;padding:18px}
  .review-summary{display:flex;gap:12px;align-items:center;justify-content:space-between;margin-bottom:14px;padding:14px 16px;background:var(--panel);border:1px solid var(--line);border-radius:8px}
  .review-summary strong{display:block;color:var(--ink);font-size:16px}.review-summary .kv{max-width:680px}
  .decision-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:10px}
  .review-card{min-height:0;padding:12px 14px}.review-card .context{margin-top:6px;color:var(--fg);font-size:12px}
  .review-card .decision{margin-top:7px;color:var(--ink);font-size:13px}.review-card .decision b{color:var(--warn)}
  .review-actions{display:flex;gap:7px;align-items:center;flex-wrap:wrap;margin-top:10px}.review-actions form{margin:0}
  .btn{display:inline-flex;align-items:center;background:var(--elev);color:var(--ink);border:1px solid var(--line);border-radius:6px;padding:6px 10px;cursor:pointer;font-size:12px}
  .btn.primary{background:color-mix(in srgb,var(--acc) 18%,var(--elev));border-color:var(--acc);color:var(--ink)}.btn:hover{border-color:var(--acc);color:var(--ink)}
  .handled{margin-top:18px;border-top:1px solid var(--line);padding-top:10px}.handled>summary{cursor:pointer;color:var(--dim);font-size:13px;list-style:none}
  .handled>summary::-webkit-details-marker{display:none}.handled>summary::before{content:"▸ ";color:var(--acc)}.handled[open]>summary::before{content:"▾ "}
  .review-detail .decision-block{background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--warn);border-radius:8px;padding:12px 14px;margin:12px 0}
  .review-detail .decision-block h2{margin:0 0 5px;border:0;padding:0;font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--dim)}
  .review-evidence{margin-top:18px;border-top:1px solid var(--line);padding-top:10px}.review-evidence summary{cursor:pointer;color:var(--dim)}
  @media(max-width:720px){.review-summary{align-items:flex-start;flex-direction:column}.decision-grid{grid-template-columns:1fr}.review-page{padding:12px}.review-actions .btn,.review-actions button{min-height:44px}}
</style>`;

function reviewCard(r: PrReview): string {
  const merge = r.verdict === "merge-ready" && r.prUrl
    ? `<a class="btn primary" href="${esc(r.prUrl)}" target="_blank" rel="noreferrer noopener">Review &amp; merge</a>`
    : "";
  const requeue = r.status === "needs-you"
    ? `<form method="post" action="/review/requeue"><input type="hidden" name="id" value="${esc(r.id)}"><button type="submit">Requeue tonight</button></form>`
    : "";
  return `<article class="card review-card" style="border-left-color:var(--acc2)">
    <div class="badges">
      <span class="badge type">${esc(r.verdict)}</span>
      <span class="badge">${esc(r.goal)}</span>
    </div>
    <a class="title" href="/review/${encodeURIComponent(r.id)}">${esc(r.title)}</a>
    ${r.whatItMeans ? `<div class="context">${esc(r.whatItMeans)}</div>` : ""}
    ${r.recommendation ? `<div class="decision"><b>Recommendation:</b> ${esc(r.recommendation)}</div>` : ""}
    <div class="review-actions">${merge}${requeue}<a class="btn" href="/review/${encodeURIComponent(r.id)}">Details</a></div>
  </article>`;
}

function caseCard(c: ReviewCase): string {
  const last = c.attempts[c.attempts.length - 1];
  const needsDecision = c.state === "dead";
  return `<article class="card review-card" style="border-left-color:${needsDecision ? "var(--err)" : "var(--ok)"}">
    <div class="badges"><span class="badge type">${needsDecision ? "needs attention" : "handled"}</span><span class="badge">${esc(c.goal)}</span></div>
    <a class="title" href="/review/${encodeURIComponent(c.id)}">${esc(c.title)}</a>
    <div class="context">${needsDecision ? "The automated review could not finish." : "This branch was already part of the main codebase."}</div>
    <div class="decision"><b>${needsDecision ? "Recommendation:" : "Outcome:"}</b> ${needsDecision ? "Requeue after checking the last failure." : "No action needed."}</div>
    <div class="review-actions">${needsDecision ? `<form method="post" action="/review/requeue"><input type="hidden" name="id" value="${esc(c.id)}"><button type="submit">Requeue tonight</button></form>` : ""}<a class="btn" href="/review/${encodeURIComponent(c.id)}">Details</a></div>
    ${last && needsDecision ? `<span class="kv">Last issue: ${esc(last.message)}</span>` : ""}
  </article>`;
}

/** Reviews: morning PR reviews grouped into lanes by status. Each card shows
 *  title, repo, verdict, recommendation, a PR link, and risks. Empty → an
 *  empty state (the reviews dir may be absent / unwritten). */
export function renderReviews(reviews: PrReview[], cases: ReviewCase[] = []): string {
  if (!reviews.length && !cases.length) {
    return layout("reviews", `<div class="wrap"><div class="empty" style="padding:24px">no PR reviews yet — the morning review pass writes them after the overnight run pushes branches</div></div>`);
  }
  const decisions = reviews.filter((r) => r.status === "needs-you");
  const dead = cases.filter((c) => c.state === "dead");
  const handledReviews = reviews.filter((r) => r.status !== "needs-you");
  const alreadyMerged = cases.filter((c) => c.state === "already-merged");
  const attentionCount = decisions.length + dead.length;
  const attention = [...decisions.map(reviewCard), ...dead.map(caseCard)].join("");
  const handled = [...handledReviews.map(reviewCard), ...alreadyMerged.map(caseCard)].join("");
  const summary = attentionCount === 1 ? "1 decision needs you" : `${attentionCount} decisions need you`;
  return layout("reviews", `${REVIEW_STYLE}<main class="review-page">
    <section class="review-summary"><div><strong>${summary}</strong><div class="kv">Everything else is handled. Open a card only when you want the supporting evidence.</div></div><a class="btn" href="/nightly">View overnight queue</a></section>
    <h2 class="secthdr">Decide now <span class="count">${attentionCount}</span></h2>
    <div class="decision-grid">${attention || `<div class="empty">nothing needs you right now</div>`}</div>
    <details class="handled"><summary>Handled <span class="count">${handledReviews.length + alreadyMerged.length}</span></summary><div class="decision-grid" style="margin-top:10px">${handled || `<div class="empty">nothing handled yet</div>`}</div></details>
  </main>`);
}

/** One review, translated for a human decision. Machine evidence remains
 * available in a native disclosure rather than competing with the decision. */
export function renderReviewDetail(item: PrReview | ReviewCase): string {
  if ("version" in item) {
    const last = item.attempts[item.attempts.length - 1];
    const needsDecision = item.state === "dead";
    const actions = needsDecision
      ? `<form method="post" action="/review/requeue"><input type="hidden" name="id" value="${esc(item.id)}"><button type="submit">Requeue tonight</button></form>`
      : `<span class="kv">No action needed.</span>`;
    return layout("reviews", `${REVIEW_STYLE}<main class="detail review-detail"><a href="/reviews" class="kv">← reviews</a><h1>${esc(item.title)}</h1>
      <div class="decision-block"><h2>What happened</h2><div>${needsDecision ? "The automated review stopped after repeated failures." : "The branch was already included in the main codebase."}</div></div>
      <div class="decision-block"><h2>My recommendation</h2><div>${needsDecision ? "Check the last failure, then requeue it for another overnight pass." : "No action needed."}</div></div>
      <div class="review-actions">${actions}</div>
      <details class="review-evidence"><summary>Technical evidence</summary><p class="kv">Branch: ${esc(item.branch)}</p><p class="kv">Last issue: ${esc(last?.message ?? "none — Git/GitHub reported the branch already integrated")}</p></details>
    </main>`);
  }
  const merge = item.verdict === "merge-ready" && item.prUrl
    ? `<a class="btn primary" href="${esc(item.prUrl)}" target="_blank" rel="noreferrer noopener">Review &amp; merge</a>`
    : "";
  const requeue = item.status === "needs-you"
    ? `<form method="post" action="/review/requeue"><input type="hidden" name="id" value="${esc(item.id)}"><button type="submit">Requeue tonight</button></form>`
    : "";
  return layout("reviews", `${REVIEW_STYLE}<main class="detail review-detail"><a href="/reviews" class="kv">← reviews</a><h1>${esc(item.title)}</h1>
    <div class="badges"><span class="badge type">${esc(item.verdict)}</span><span class="badge">${esc(item.goal)}</span></div>
    <div class="decision-block"><h2>What happened</h2><div>${esc(item.whatWasDone)}</div></div>
    <div class="decision-block"><h2>Why it matters</h2><div>${esc(item.whatItMeans)}</div></div>
    <div class="decision-block"><h2>My recommendation</h2><div>${esc(item.recommendation)}</div></div>
    <div class="review-actions">${merge}${requeue}${item.prUrl ? `<a class="btn" href="${esc(item.prUrl)}" target="_blank" rel="noreferrer noopener">Open PR</a>` : ""}</div>
    <details class="review-evidence"><summary>Technical evidence</summary>
      <p class="kv">Repository: ${esc(item.repo)} · Branch: ${esc(item.branch)} · Base: ${esc(item.base)}</p>
      <p class="kv">Change size: ${item.diffstat.files} files, +${item.diffstat.insertions}, −${item.diffstat.deletions} · Mergeable: ${item.mergeable == null ? "unknown" : item.mergeable ? "yes" : "no"}</p>
      ${item.risks.length ? `<h2>Risks</h2><ul>${item.risks.map((r) => `<li>${esc(r)}</li>`).join("")}</ul>` : ""}
      ${item.commits.length ? `<h2>Commits</h2><ul>${item.commits.map((c) => `<li>${esc(c)}</li>`).join("")}</ul>` : ""}
    </details>
  </main>`);
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
