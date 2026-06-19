/**
 * sr_gauntlet ledger adapter — read-only overlay of investigation state.
 *
 * The SR gauntlet (~/700_datax/sr_gauntlet) auto-investigates open DataX SRs
 * and records what it has looked at in state/ledger.json, keyed by the SR's
 * Firestore doc id (== sr_analyzer ticket.externalId). That key is the join
 * the SR tile uses to badge each card with "investigated on <date>".
 *
 * Note on granularity: the ledger records *that* an SR was investigated (date +
 * run id), not the fine verdict (investigated vs inconclusive) — run.sh parses
 * the verdict from the run's agent log but does not persist it here. Surfacing
 * the verdict would mean reading one REPORT.md per card; deferred deliberately
 * to keep this a single cheap file read. Presence ⇒ investigated.
 */

import { readFile } from "node:fs/promises";

export interface LedgerEntry {
  hash: string;
  investigatedAt: string; // YYYY-MM-DD
  run: string; // run dir name under investigations/
}

export type Ledger = Record<string, LedgerEntry>;

/** Read the gauntlet ledger. A missing file (gauntlet never ran on this host)
 * is not an error — it yields an empty overlay so every card simply renders
 * "not yet investigated". Any other read/parse failure is swallowed to empty
 * for the same reason: the overlay is best-effort enrichment, never load-bearing
 * for the board itself. */
export async function loadLedger(path: string): Promise<Ledger> {
  let text: string;
  try {
    text = await readFile(path, "utf-8");
  } catch {
    return {};
  }
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Ledger;
    }
  } catch {
    /* fall through to empty */
  }
  return {};
}
