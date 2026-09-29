/**
 * sr_gauntlet state adapter — read-only view of the SR gauntlet's state dir.
 *
 * The SR gauntlet (~/700_datax/gauntlets/sr_gauntlet) polls DataX Firestore every 15
 * minutes and keeps two files the datax_* tools read:
 *
 *   sr-cache.json  every SR, refreshed incrementally, with SR2's derivations
 *                  (`effectivePhase`, `effectiveNeedsReply`) stamped by the
 *                  gauntlet and `syncedAt` = last whole-collection read. This
 *                  replaced the sr_analyzer service (retired 2026-09-28): the
 *                  gauntlet already paid for the Firestore reads, so the
 *                  gateway still holds no Firebase credentials and computes no
 *                  SR2 mapping of its own.
 *   ledger.json    what the gauntlet has investigated, keyed by the same
 *                  Firestore doc id. Presence of `investigatedAt` badges a card.
 *
 * Boundary validation is hand-written (the gateway has no zod dependency).
 */

import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const CACHE_FILE = "sr-cache.json";
export const LEDGER_FILE = "ledger.json";

/** One SR as the board renders it. `id` is the Firestore webRequests doc id. */
export interface SrRecord {
  id: string;
  title: string;
  submitterName: string | null;
  phase: string;
  needsReply: boolean;
  service: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface SrCache {
  /** Last successful whole-collection Firestore read, or null if never. */
  syncedAt: string | null;
  records: SrRecord[];
}

export interface LedgerEntry {
  investigatedAt?: string; // YYYY-MM-DD; absent on failed attempts
  run: string; // run dir name under investigations/
}

export type Ledger = Record<string, LedgerEntry>;

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

const str = (v: unknown): string | null => (typeof v === "string" && v ? v : null);

/** Read and validate the SR cache. Throws on a missing or unreadable file, or
 * on a cache written before the gauntlet stamped SR2 phases — the board is
 * load-bearing, so the tool must fail loudly rather than render an empty or
 * mis-phased board. */
export async function loadCache(stateDir: string): Promise<SrCache> {
  const path = join(stateDir, CACHE_FILE);
  const parsed: unknown = JSON.parse(await readFile(path, "utf-8"));
  if (!isObject(parsed) || !isObject(parsed.srs)) {
    throw new Error(`${path} has no srs map`);
  }
  const records: SrRecord[] = [];
  for (const [id, raw] of Object.entries(parsed.srs)) {
    if (!isObject(raw)) continue;
    const phase = str(raw.effectivePhase);
    if (!phase) {
      throw new Error(
        `${path} record ${id} has no effectivePhase — the gauntlet has not rewritten the cache since its phase stamp shipped`,
      );
    }
    const createdAt = str(raw.createdAt) ?? "";
    records.push({
      id,
      title: str(raw.title) ?? "(untitled)",
      submitterName: str(raw.name),
      phase,
      needsReply: raw.effectiveNeedsReply === true,
      service: str(raw.service),
      createdAt,
      updatedAt: str(raw.updatedAt) ?? createdAt,
    });
  }
  return { syncedAt: str(parsed.syncedAt), records };
}

/** Read the gauntlet ledger. A missing or unparseable file yields an empty
 * overlay: the badge is best-effort enrichment, never load-bearing for the
 * board itself. */
export async function loadLedger(stateDir: string): Promise<Ledger> {
  let text: string;
  try {
    text = await readFile(join(stateDir, LEDGER_FILE), "utf-8");
  } catch {
    return {};
  }
  try {
    const parsed = JSON.parse(text);
    if (isObject(parsed)) return parsed as Ledger;
  } catch {
    /* fall through to empty */
  }
  return {};
}
