// Read-only mirror of the sr_gauntlet's completed investigations as refinery
// projects. Rather than touch Firestore (creds, network, PII), this reads the
// LOCAL investigation outputs the gauntlet already wrote:
//   <gauntletDir>/investigations/<date>-<srId>/{sr.json, REPORT.md}
// SRs show as read-only datax-sr cards in the Done lane, linking to their REPORT.
// sr_gauntlet's run.sh + Discord are untouched.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { Item } from "../contracts.js";

export const SR_PREFIX = "sr:";
export const SR_GENRE = "datax-sr";

interface SrMeta {
  id?: string;
  title?: string;
  status?: string;
  phase?: string;
  name?: string;
  email?: string;
}

/** Read a file from an investigation run dir relative to baseDir (traversal-guarded). */
export function readRunFile(baseDir: string, run: string, name: string): string | null {
  if (!run || run.includes("..") || run.startsWith("/")) return null;
  const path = join(baseDir, run.replace(/\/$/, ""), name);
  return existsSync(path) ? readFileSync(path, "utf8") : null;
}

/** Read completed SR investigations as read-only mirror Items. */
export function srInvestigationProjects(gauntletDir: string): Item[] {
  const base = join(gauntletDir, "investigations");
  if (!existsSync(base)) return [];
  const out: Item[] = [];
  for (const runName of readdirSync(base)) {
    const dir = join(base, runName);
    if (!statSync(dir).isDirectory()) continue;
    const srJson = join(dir, "sr.json");
    if (!existsSync(srJson)) continue;
    let meta: SrMeta = {};
    try {
      meta = JSON.parse(readFileSync(srJson, "utf8")) as SrMeta;
    } catch {
      meta = {};
    }
    const hasReport = existsSync(join(dir, "REPORT.md"));
    out.push({
      id: `${SR_PREFIX}${runName}`,
      genre: SR_GENRE,
      phase: "investigated",
      phaseStatus: "passed", // a completed investigation
      payload: {
        title: meta.title || meta.id || runName,
        srId: meta.id ?? "",
        srStatus: meta.status ?? "",
        srPhase: meta.phase ?? "",
        customer: meta.name ?? "",
        email: meta.email ?? "",
        run: `investigations/${runName}/`,
        hasReport,
        readonly: true,
        source: "sr_gauntlet investigation",
      },
      history: [],
    });
  }
  out.sort((a, b) => b.id.localeCompare(a.id)); // newest first
  return out;
}
