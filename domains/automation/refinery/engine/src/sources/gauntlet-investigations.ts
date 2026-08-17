// Read-only mirror of a standalone gauntlet's completed investigations as
// refinery Items — the generic successor of sr-investigations.ts, driven by a
// GauntletView shim (gauntlet-views.ts) so sr_gauntlet and dx1_gauntlet are
// two shims over one reader. Rather than touch Firestore (creds, network,
// PII), this reads the LOCAL run dirs the gauntlet already wrote:
//   <gauntletDir>/investigations/<runName>/{<metaFile>, REPORT.md}
// Runs show as read-only cards on the gauntlet's board page, linking to their
// REPORT. The gauntlet's run.sh + Discord are untouched.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { Item } from "../contracts.js";
import { GauntletView } from "./gauntlet-views.js";

/** Read a file from an investigation run dir relative to baseDir (traversal-guarded). */
export function readRunFile(baseDir: string, run: string, name: string): string | null {
  if (!run || run.includes("..") || run.startsWith("/")) return null;
  const path = join(baseDir, run.replace(/\/$/, ""), name);
  return existsSync(path) ? readFileSync(path, "utf8") : null;
}

/** Read a gauntlet's completed investigations as read-only mirror Items. */
export function gauntletInvestigationProjects(view: GauntletView, gauntletDir: string): Item[] {
  const base = join(gauntletDir, "investigations");
  if (!existsSync(base)) return [];
  const extras = view.runExtras?.(gauntletDir) ?? new Map<string, Record<string, unknown>>();
  const out: Item[] = [];
  for (const runName of readdirSync(base)) {
    const dir = join(base, runName);
    if (!statSync(dir).isDirectory()) continue;
    const metaPath = join(dir, view.metaFile);
    if (!existsSync(metaPath)) continue;
    let meta: Record<string, unknown> = {};
    try {
      meta = JSON.parse(readFileSync(metaPath, "utf8")) as Record<string, unknown>;
    } catch {
      meta = {};
    }
    const hasReport = existsSync(join(dir, "REPORT.md"));
    out.push({
      id: `${view.prefix}${runName}`,
      pipeline: view.pipeline,
      step: view.step,
      state: "passed", // a completed investigation
      payload: { ...view.payloadFromMeta(meta, runName, hasReport), ...(extras.get(runName) ?? {}) },
      history: [],
    });
  }
  out.sort((a, b) => b.id.localeCompare(a.id)); // newest first
  return out;
}
