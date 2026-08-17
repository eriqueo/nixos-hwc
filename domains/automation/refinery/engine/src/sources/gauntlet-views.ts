// Gauntlet VIEW shims — the per-gauntlet data that drives ONE board page
// component (render.ts renderGauntletBoard/renderGauntletDetail) and ONE
// mirror reader (gauntlet-investigations.ts). sr and dx1 are two entries over
// the same component; a third gauntlet with the same run-dir shape is one more
// entry here + a dispatch contract YAML (gauntlets/<id>.yaml) — no renderer
// edit. Sibling of GAUNTLET_CONFIGS (pipelines/gauntlet-config.ts), which
// carries the EXECUTOR knobs; this carries the DISPLAY knobs. Two axes, two
// tables, one producer each.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Item } from "../contracts.js";

/** A CSS-only tab on the detail page backed by files in the run dir. A
 * single-file tab renders the content bare; a multi-file tab (dx1 Evidence =
 * context.md + FINDINGS.md) renders each PRESENT file as a named section —
 * absent files are simply skipped, never an error. */
export interface GauntletTab {
  key: string; // radio id suffix (srt-<key>)
  label: string;
  files: string[]; // filenames within the run dir, render order
  empty: string; // placeholder when none of the files exist
}

/** A run-dir file read for the detail page / exports. */
export interface RunFile {
  name: string;
  content: string;
}

/** Everything the detail page + exports read off one run dir. */
export interface GauntletRunBundle {
  /** Present files per tab key, in the tab's declared order. */
  tabs: Record<string, RunFile[]>;
  /** view.contextFile content (SR's Details appendix), if configured+present. */
  context: string | null;
  /** view.detailFiles contents (dx1's case.json/verdict.json), present only. */
  detail: RunFile[];
}

export interface GauntletDetailHeader {
  /** Big header line (SR: customer; DX1: agent). */
  title: string;
  /** Category chip (SR: status; DX1: verdict). */
  cat: string;
  /** One-line question / problem statement under the title. */
  question: string;
  /** Id passed to run-now; empty string hides the button. */
  runId: string;
}

export interface GauntletView {
  key: string; // url segment + nav key + caps.json key ("sr", "dx1")
  label: string; // nav tab label
  prefix: string; // Item id prefix ("sr:")
  pipeline: string; // Item.pipeline for mirror cards
  metaFile: string; // per-run metadata JSON the runner writes (sr.json / case.json)
  step: string; // Item.step for mirror cards
  source: string; // payload.source provenance line
  capDefault: number;
  capLabel: string; // cap form label
  capNote: string; // cap form caption (after "<n> investigations · ")
  emptyText: string; // board empty state
  laneFallback: string; // lane when laneOf yields nothing
  /** Payload field the lane keying reads (data-driven lanes). */
  laneField: string;
  /** Run-now form: field name + copy. null = gauntlet has no run-now. */
  runNow: { field: string; button: string; title: (id: string) => string; caption: string } | null;
  /** Extra links rendered beside the cap form (dx1: the fleet view). A view
   * without links renders exactly as before — byte-parity preserved. */
  links?: { href: string; label: string }[];
  /** Sortable date for a run card (ISO-ish string; "" = unknown, sorts last).
   * Feeds the card wrapper's data-date for the enhancer's in-lane sort. */
  sortDate?: (item: Item) => string;
  /** File-backed tabs, in order; the composed "details" tab is appended by the renderer. */
  tabs: GauntletTab[];
  /** Detail context file folded into the Details tab (below the meta rows) as
   * "## Customer context". SR only; dx1's Details stays technical. */
  contextFile?: string;
  /** Raw run-dir files appended to the Details tab (and its export) as fenced
   * blocks — dx1: case.json + verdict.json. Absent files are skipped. */
  detailFiles?: string[];
  /** meta JSON (+ run dir facts) → mirror Item payload. */
  payloadFromMeta: (meta: Record<string, unknown>, runName: string, hasReport: boolean) => Record<string, unknown>;
  /** Optional per-run payload enrichment read ONCE per listing from gauntlet
   * state (dx1: verdicts live in state/ledger.json, not case.json). Keyed by
   * run dir name; merged over payloadFromMeta's output. */
  runExtras?: (gauntletDir: string) => Map<string, Record<string, unknown>>;
  /** Detail header facts off the payload. */
  headerOf: (item: Item) => GauntletDetailHeader;
  /** Markdown body of the Details tab (meta rows; renderer appends context). */
  detailsMd: (item: Item) => string;
}

const str = (v: unknown): string => (typeof v === "string" ? v : "");
const pl = (item: Item): Record<string, unknown> =>
  item.payload && typeof item.payload === "object" ? (item.payload as Record<string, unknown>) : {};

// ── SR — the original page, verbatim (parity-gated by test/golden/) ─────────

const SR_VIEW: GauntletView = {
  key: "sr",
  label: "SR",
  prefix: "sr:",
  pipeline: "datax-sr",
  metaFile: "sr.json",
  step: "investigated",
  source: "sr_gauntlet investigation",
  capDefault: 5,
  capLabel: "Max SRs per run:",
  capNote: "sr_gauntlet runs @ 06:30 (this cap)",
  emptyText: "no SR investigations yet — the gauntlet writes them under sr_gauntlet/investigations/",
  laneField: "srStatus",
  laneFallback: "investigated",
  runNow: {
    field: "srId",
    button: "▶ re-investigate now",
    title: (id) => `run the SR gauntlet on ${id} now`,
    caption: "forces a fresh investigation; the report updates when it finishes",
  },
  tabs: [
    { key: "gameplan", label: "Gameplan", files: ["REPORT.md"], empty: "no REPORT.md for this investigation yet" },
    { key: "thread", label: "Thread", files: ["sr.md"], empty: "no thread (sr.md) captured" },
  ],
  contextFile: "context.md",
  payloadFromMeta: (meta, runName, hasReport) => ({
    title: str(meta.title) || str(meta.id) || runName,
    srId: str(meta.id),
    srStatus: str(meta.status),
    srPhase: str(meta.phase),
    customer: str(meta.name),
    email: str(meta.email),
    run: `investigations/${runName}/`,
    hasReport,
    readonly: true,
    source: "sr_gauntlet investigation",
  }),
  headerOf: (item) => {
    const p = pl(item);
    return {
      title: str(p.customer) || str(p.srId) || item.id,
      cat: str(p.srStatus) || "investigated",
      question: str(p.title),
      runId: str(p.srId),
    };
  },
  detailsMd: (item) => {
    const p = pl(item);
    const customer = str(p.customer) || str(p.srId) || item.id;
    const email = str(p.email);
    const cat = str(p.srStatus) || "investigated";
    const phase = str(p.srPhase);
    return [
      `**Customer:** ${customer}`,
      email ? `**Email:** ${email}` : "",
      `**Status:** ${cat}${phase ? ` · phase ${phase}` : ""}`,
      typeof p.run === "string" ? `**Run:** ${p.run}` : "",
    ].filter(Boolean).join("\n");
  },
  // sr run dirs are date-prefixed (investigations/<YYYY-MM-DD>-<srId>/).
  sortDate: (item) => {
    const m = str(pl(item).run).match(/investigations\/(\d{4}-\d{2}-\d{2})-/);
    return m ? m[1]! : "";
  },
};

// ── DX1 — case-ledger investigations (dx1_gauntlet), same component ─────────
// Run-dir contract (runner README "Interface contract", re-verified
// 2026-08-16 post-rework; see gauntlets/dx1_gauntlet.yaml):
//   investigations/<caseFingerprint>_<stateHash>/   (fingerprint keeps its ":")
//     case.json    — { caseFingerprint, stateHash, agentId, agentName, orgId,
//                      orgName, family, triage, state, … } (queue snapshot)
//     REPORT.md    — the BRIEF (status line + TL;DR)
//     FINDINGS.md  — the DOSSIER (cited; absent on pre-rework runs)
//     context.md   — the aggregated evidence pack
//     verdict.json — machine verdict fields (impact/faultDomains/confidence/…)
//   state/ledger.json — { [fingerprint]: { caseFingerprint, stateHash,
//     verdict, investigatedAt, run } } — the VERDICT source; joined onto the
//     mirror by run name (runExtras). A run without a ledger entry (failed or
//     superseded) lanes as "pending".

const DX1_VIEW: GauntletView = {
  key: "dx1",
  label: "DX1",
  prefix: "dx1:",
  pipeline: "dx1-case",
  metaFile: "case.json",
  step: "investigated",
  source: "dx1_gauntlet investigation",
  capDefault: 3,
  capLabel: "Max cases per run:",
  capNote: "dx1_gauntlet investigates open dx1Cases (this cap)",
  emptyText: "no case investigations yet — the gauntlet writes them under dx1_gauntlet/investigations/",
  laneField: "verdict",
  laneFallback: "pending",
  runNow: {
    field: "caseId",
    button: "▶ re-investigate now",
    title: (id) => `run the DX1 gauntlet on case ${id} now`,
    caption: "forces a fresh investigation of this case; the report updates when it finishes",
  },
  links: [{ href: "/dx1/fleet", label: "📊 fleet cohort health" }],
  tabs: [
    { key: "gameplan", label: "Report", files: ["REPORT.md"], empty: "no REPORT.md for this investigation yet" },
    // Evidence = the pack the agent started from + the cited dossier it wrote.
    // FINDINGS.md is absent on pre-rework runs — present files render, gaps skip.
    { key: "thread", label: "Evidence", files: ["context.md", "FINDINGS.md"], empty: "no evidence (context.md / FINDINGS.md) captured" },
  ],
  // Details stays technical (case.json / verdict.json / run metadata) — the
  // evidence pack lives in the Evidence tab, not duplicated here.
  detailFiles: ["case.json", "verdict.json"],
  payloadFromMeta: (meta, runName, hasReport) => ({
    title: [str(meta.agentName), str(meta.family)].filter(Boolean).join(" · ") || runName,
    caseFingerprint: str(meta.caseFingerprint),
    stateHash: str(meta.stateHash),
    family: str(meta.family),
    triage: str(meta.triage),
    agentName: str(meta.agentName),
    orgName: str(meta.orgName),
    run: `investigations/${runName}/`,
    hasReport,
    readonly: true,
    source: "dx1_gauntlet investigation",
  }),
  // Verdicts live in the runner's ledger, not case.json — join by run name.
  runExtras: (gauntletDir) => {
    const out = new Map<string, Record<string, unknown>>();
    const ledgerPath = join(gauntletDir, "state", "ledger.json");
    if (!existsSync(ledgerPath)) return out;
    let ledger: Record<string, unknown> = {};
    try {
      ledger = JSON.parse(readFileSync(ledgerPath, "utf8")) as Record<string, unknown>;
    } catch {
      return out;
    }
    for (const entry of Object.values(ledger)) {
      if (!entry || typeof entry !== "object") continue;
      const e = entry as Record<string, unknown>;
      if (typeof e.run === "string" && typeof e.verdict === "string" && e.verdict) {
        out.set(e.run, {
          verdict: e.verdict,
          ...(typeof e.investigatedAt === "string" ? { investigatedAt: e.investigatedAt } : {}),
        });
      }
    }
    return out;
  },
  headerOf: (item) => {
    const p = pl(item);
    return {
      title: str(p.agentName) || str(p.caseFingerprint) || item.id,
      cat: str(p.verdict) || "pending",
      question: str(p.title),
      runId: str(p.caseFingerprint),
    };
  },
  detailsMd: (item) => {
    const p = pl(item);
    return [
      p.caseFingerprint ? `**Case:** \`${str(p.caseFingerprint)}\`` : "",
      p.stateHash ? `**State hash:** \`${str(p.stateHash)}\`` : "",
      p.orgName ? `**Org:** ${str(p.orgName)}` : "",
      p.family ? `**Family:** ${str(p.family)}${p.triage ? ` (triage: ${str(p.triage)})` : ""}` : "",
      `**Verdict:** ${str(p.verdict) || "pending"}`,
      typeof p.run === "string" ? `**Run:** ${p.run}` : "",
    ].filter(Boolean).join("\n");
  },
  // dx1 run dirs carry no date — the ledger's investigatedAt (joined in
  // runExtras) is the date; runs without a ledger entry sort last.
  sortDate: (item) => str(pl(item).investigatedAt),
};

/** The view registry — page order is nav order. */
export const GAUNTLET_VIEWS: GauntletView[] = [SR_VIEW, DX1_VIEW];

export function gauntletViewByKey(key: string): GauntletView | null {
  return GAUNTLET_VIEWS.find((v) => v.key === key) ?? null;
}

/** The view whose id-prefix matches an item id (detail/report routing). */
export function gauntletViewForId(id: string): GauntletView | null {
  return GAUNTLET_VIEWS.find((v) => id.startsWith(v.prefix)) ?? null;
}

// ── Exports — one producer for the download compositions ───────────────────
// Registry-driven: every gauntlet detail page offers per-tab downloads plus a
// combined file. Pure markdown assembly over the run bundle; the HTTP shell
// only serves the result with Content-Disposition: attachment.

const langOf = (name: string): string => (name.endsWith(".json") ? "json" : "");

/** A tab's markdown body: its present files, multi-file tabs section-headed.
 * Shared by the detail panel (via mdToHtml) and the export — one composition. */
export function tabMd(tab: GauntletTab, bundle: GauntletRunBundle): string | null {
  const files = bundle.tabs[tab.key] ?? [];
  if (files.length === 0) return null;
  // Section headers only when there is more than one PRESENT file — a
  // pre-rework dx1 run (context.md alone, no FINDINGS.md) renders bare, like
  // any single-file tab.
  if (files.length === 1) return files[0]!.content;
  return files.map((f) => `# ${f.name}\n\n${f.content}`).join("\n\n---\n\n");
}

/** The Details tab as markdown (meta rows + context appendix + raw files) —
 * the same composition the renderer shows, shared so the export can't drift. */
export function detailsExportMd(view: GauntletView, item: Item, bundle: GauntletRunBundle): string {
  const parts = [view.detailsMd(item)];
  if (view.contextFile) {
    parts.push(bundle.context ? `## Customer context\n\n${bundle.context}` : `_no ${view.contextFile}_`);
  }
  for (const f of bundle.detail) {
    parts.push(`## ${f.name}\n\n\`\`\`${langOf(f.name)}\n${f.content.trimEnd()}\n\`\`\``);
  }
  // Single-\n join: byte-compatible with the pre-export SR Details panel
  // (the old renderer joined with "\n"; markdown treats both the same here).
  return parts.filter(Boolean).join("\n");
}

/** Compose one export. part = a tab key, "details", or "all". Null when the
 * part is unknown; an empty part still exports (placeholder body) so the
 * button never 404s on a sparse run dir. */
export function buildGauntletExport(
  view: GauntletView,
  item: Item,
  bundle: GauntletRunBundle,
  part: string,
): { filename: string; markdown: string } | null {
  const run = pl(item).run;
  const runName = typeof run === "string"
    ? run.replace(/^investigations\//, "").replace(/\/$/, "")
    : item.id.slice(view.prefix.length);
  // ":" (case fingerprints) is unfriendly in download filenames on some OSes —
  // same "+" encoding as the run-now spool.
  const base = runName.replace(/:/g, "+").replace(/[^A-Za-z0-9._+-]/g, "") || view.key;
  const name = (p: string) => `${base}-${p}.md`;

  const tab = view.tabs.find((t) => t.key === part);
  if (tab) return { filename: name(part), markdown: tabMd(tab, bundle) ?? `_${tab.empty}_` };
  if (part === "details") return { filename: name(part), markdown: detailsExportMd(view, item, bundle) };
  if (part === "all") {
    const head = view.headerOf(item);
    const sections = [
      `# ${head.title}${head.question ? ` — ${head.question}` : ""}`,
      ...view.tabs.map((t) => `# ${t.label}\n\n${tabMd(t, bundle) ?? `_${t.empty}_`}`),
      `# Details\n\n${detailsExportMd(view, item, bundle)}`,
    ];
    return { filename: name("all"), markdown: sections.join("\n\n---\n\n") };
  }
  return null;
}
