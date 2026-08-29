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
import { GauntletRunBundle, GauntletView, RunFile } from "./gauntlet-views.js";

/** Read a file from an investigation run dir relative to baseDir (traversal-guarded). */
export function readRunFile(baseDir: string, run: string, name: string): string | null {
  if (!run || run.includes("..") || run.startsWith("/")) return null;
  const path = join(baseDir, run.replace(/\/$/, ""), name);
  return existsSync(path) ? readFileSync(path, "utf8") : null;
}

/** Read everything a view's detail page + exports need off one run dir:
 * per-tab present files, the Details context appendix, and the raw detail
 * files. One reader, shared by the detail route and the export route. */
export function readRunBundle(view: GauntletView, baseDir: string, run: string): GauntletRunBundle {
  const present = (names: string[]): RunFile[] =>
    names.flatMap((name) => {
      const content = readRunFile(baseDir, run, name);
      return content === null ? [] : [{ name, content }];
    });
  return {
    tabs: Object.fromEntries(view.tabs.map((t) => [t.key, present(t.files)])),
    context: view.contextFile ? readRunFile(baseDir, run, view.contextFile) : null,
    detail: present(view.detailFiles ?? []),
  };
}

/** Read a gauntlet's completed investigations as read-only mirror Items. */
export function gauntletInvestigationProjects(view: GauntletView, gauntletDir: string): Item[] {
  const base = join(gauntletDir, "investigations");
  if (!existsSync(base)) return [];
  const extras = view.runExtras?.(gauntletDir) ?? new Map<string, Record<string, unknown>>();
  // SR's ledger is the authority for which run is current and whether it
  // completed. Old run directories remain useful history, never fresh work.
  if (view.key === "sr") {
    const cachePath = join(gauntletDir, "state", "sr-cache.json");
    let sourceRecords: Record<string, unknown> | null = null;
    let sourceAsOf = "";
    if (existsSync(cachePath)) {
      try {
        const cache = JSON.parse(readFileSync(cachePath, "utf8")) as Record<string, unknown>;
        if (cache.srs && typeof cache.srs === "object" && !Array.isArray(cache.srs)) {
          sourceRecords = cache.srs as Record<string, unknown>;
          sourceAsOf = typeof cache.watermark === "string" ? cache.watermark : "";
        }
      } catch { /* unavailable cache must not hide a live failed investigation */ }
    }
    const ledgerPath = join(gauntletDir, "state", "ledger.json");
    if (existsSync(ledgerPath)) {
      try {
        const ledger = JSON.parse(readFileSync(ledgerPath, "utf8")) as Record<string, unknown>;
        for (const [srId, raw] of Object.entries(ledger)) {
          if (!raw || typeof raw !== "object") continue;
          const entry = raw as Record<string, unknown>;
          if (typeof entry.run !== "string" || !entry.run) continue;
          const source = sourceRecords?.[srId];
          const sourceRecord = source && typeof source === "object" && !Array.isArray(source)
            ? source as Record<string, unknown>
            : null;
          const status = typeof sourceRecord?.status === "string" ? sourceRecord.status.toLowerCase() : "";
          const phase = typeof sourceRecord?.phaseId === "string" ? sourceRecord.phaseId.toLowerCase() : "";
          const sourceDisposition = sourceRecords === null
            ? "unknown"
            : sourceRecord === null
              ? "missing"
              : status === "closed" || phase === "closed"
                ? "closed"
                : "live";
          extras.set(entry.run, {
            ...(extras.get(entry.run) ?? {}),
            ledgerCurrent: true,
            ledgerState: entry.failed === true ? "failed" : entry.provenance ? "completed" : "legacy",
            sourceDisposition,
            ...(sourceAsOf ? { sourceAsOf } : {}),
          });
        }
      } catch { /* malformed ledger leaves every run as bounded history */ }
    }
  }
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
    const filePayload = Object.fromEntries((view.payloadFiles ?? []).flatMap((name) => {
      const path = join(dir, name);
      if (!existsSync(path)) return [];
      try {
        const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
        return parsed && typeof parsed === "object" && !Array.isArray(parsed)
          ? Object.entries(parsed as Record<string, unknown>)
          : [];
      } catch { return []; }
    }));
    const enriched = { ...view.payloadFromMeta(meta, runName, hasReport), ...filePayload, ...(extras.get(runName) ?? {}) };
    out.push({
      id: `${view.prefix}${runName}`,
      pipeline: view.pipeline,
      step: view.step,
      state: enriched.ledgerState === "failed" ? "failed" : "passed",
      payload: enriched,
      history: [],
    });
  }
  out.sort((a, b) => b.id.localeCompare(a.id)); // newest first
  return out;
}
