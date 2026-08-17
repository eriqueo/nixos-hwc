// DX1 fleet cohort-health snapshots — reader + vocabulary for the board's
// /dx1/fleet view. Deliberately BESPOKE (not a GauntletView): the snapshot is
// dx1-specific analytics with no second consumer; the gauntlet registry
// drives run-dir mirrors, and stretching its shim vocabulary to cover a
// cohort table would generalize on the first consumer. If a second fleet-like
// feed ever appears, extract the shape then.
//
// Source contract (dx1_gauntlet writes one snapshot per day):
//   <dx1Dir>/state/fleet-history/YYYY-MM-DD.json
// The board reads the LATEST parseable snapshot (+ the second-latest for
// trend deltas). state/ is already RO-bound into the board sandbox.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

export interface FleetMember {
  id?: string;
  name?: string;
  orgDocId?: string;
  ratio?: number;
  /** Client display name (companyName, "JT <orgID>" fallback, or null).
   * Absent on pre-2026-08-17 snapshots — render degrades to the old row. */
  org?: string | null;
  /** Per-agent window stats; null = NO RUNS IN WINDOW (a state, not zeros).
   * Absent on pre-2026-08-17 snapshots. */
  stats?: FleetMemberStats | null;
}

export interface FleetMemberStats {
  tasks: number;
  cleanPct: number | null;
  needsHelp: number;
  errors: number;
  stalls: number;
  runtimeMedianMin: number | null;
  burnMaxM: number | null;
}

export interface FleetRuntime {
  n: number;
  medianMin: number;
  p90Min: number;
  p99Min: number;
  maxMin: number;
  over10Min: number;
}

export interface FleetTokenBurn {
  tasksMeasured: number;
  medianM: number;
  p90M: number;
  maxM: number;
}

export interface FleetRates {
  agents: number;
  agentsWithTasks: number;
  tasks: number;
  pooled?: Record<string, number>;
  cleanPooledPct?: number;
  cleanPooledExclQuotaPct?: number;
  needsHelpErrExclQuotaPct?: number;
  cleanMedianPct?: number;
  runtime?: FleetRuntime | null;
  stallEvents?: number;
  tasksWithStall?: number;
  engineFamilies7d?: Record<string, number> | null;
  tokenBurnUpperBound336h?: FleetTokenBurn | null;
}

export interface FleetTemplate {
  rootId: string;
  name: string;
  author?: string;
  downloads?: number;
  cohortSize: number;
  byteIdentical?: number;
  divergedForks?: number;
  members?: FleetMember[];
  divergedMembers?: FleetMember[];
  rates: FleetRates;
  divergedRates?: FleetRates | null;
}

export interface FleetSnapshot {
  date: string;
  generatedAt?: string;
  windowDays?: number;
  method?: Record<string, unknown>;
  fleet?: { productionAgents?: number; unassignedCount?: number; unassigned?: FleetMember[] };
  templates: FleetTemplate[];
}

/** The latest parseable snapshot and (for trend deltas) the one before it.
 * Missing dir / no parseable file → { latest: null } — the view renders an
 * empty state, never an error page. */
export function readFleetSnapshots(dx1Dir: string): { latest: FleetSnapshot | null; previous: FleetSnapshot | null } {
  const dir = join(dx1Dir, "state", "fleet-history");
  if (!existsSync(dir)) return { latest: null, previous: null };
  const files = readdirSync(dir)
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.json$/.test(f))
    .sort()
    .reverse(); // newest first (date-named files sort lexically)
  const parsed: FleetSnapshot[] = [];
  for (const f of files) {
    if (parsed.length === 2) break;
    try {
      const snap = JSON.parse(readFileSync(join(dir, f), "utf8")) as FleetSnapshot;
      if (snap && Array.isArray(snap.templates)) parsed.push(snap);
    } catch {
      // a corrupt day is skipped, not fatal — older snapshots still serve
    }
  }
  return { latest: parsed[0] ?? null, previous: parsed[1] ?? null };
}

/** Trend on clean% (pooled excl-quota) vs the previous snapshot's same
 * cohort. Null when no previous snapshot / cohort / value — the view degrades
 * to no arrow. */
export function cohortCleanDelta(
  latest: FleetTemplate,
  previous: FleetSnapshot | null,
): number | null {
  const now = latest.rates.cleanPooledExclQuotaPct;
  if (typeof now !== "number" || !previous) return null;
  const prev = previous.templates.find((t) => t.rootId === latest.rootId)?.rates.cleanPooledExclQuotaPct;
  return typeof prev === "number" ? now - prev : null;
}

// Family-code badge colors — mirrors datax lib/monitoring/family-catalog.ts
// (FAMILY_CATALOG colors, frozen at copy 2026-08-17). Data-driven categorical
// color, applied inline like the FamilyBadge it models.
export const FLEET_FAMILY_COLORS: Record<string, string> = {
  P1: "#eab308",
  P2: "#f59e0b",
  P3: "#f97316",
  P4: "#fb923c",
  P5: "#fbbf24",
  D1: "#dc2626",
  D2: "#b91c1c",
  M1: "#8b5cf6",
};
export const FLEET_FAMILY_FALLBACK = "#a7aaad"; // board --dim

export function fleetFamilyColor(family: string): string {
  return FLEET_FAMILY_COLORS[family] ?? FLEET_FAMILY_FALLBACK;
}
