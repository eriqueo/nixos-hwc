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

/** A CSS-only tab on the detail page backed by a file in the run dir. */
export interface GauntletTab {
  key: string; // radio id suffix (srt-<key>)
  label: string;
  file: string; // filename within the run dir
  empty: string; // placeholder when the file is absent
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
  /** File-backed tabs, in order; the composed "details" tab is appended by the renderer. */
  tabs: GauntletTab[];
  /** Detail context file folded into the Details tab (below the meta rows). */
  contextFile: string;
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
    { key: "gameplan", label: "Gameplan", file: "REPORT.md", empty: "no REPORT.md for this investigation yet" },
    { key: "thread", label: "Thread", file: "sr.md", empty: "no thread (sr.md) captured" },
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
};

// ── DX1 — case-ledger investigations (dx1_gauntlet), same component ─────────
// Run-dir contract (verified against the live runner's run.sh/lib.mjs,
// 2026-08-16; see gauntlets/dx1_gauntlet.yaml):
//   investigations/<caseFingerprint>_<stateHash>/   (fingerprint keeps its ":")
//     case.json  — { caseFingerprint, stateHash, agentId, agentName, orgId,
//                    orgName, family, triage, state, … } (queue snapshot)
//     REPORT.md  — the investigation report (verdict token in agent output)
//     context.md — the aggregated evidence pack
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
  tabs: [
    { key: "gameplan", label: "Report", file: "REPORT.md", empty: "no REPORT.md for this investigation yet" },
    { key: "thread", label: "Evidence", file: "context.md", empty: "no evidence pack (context.md) captured" },
  ],
  contextFile: "context.md",
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
        out.set(e.run, { verdict: e.verdict });
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
