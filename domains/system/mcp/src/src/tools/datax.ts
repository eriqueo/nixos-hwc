/**
 * datax_* — DataX support + service health for the workbench DataX hub.
 *
 * These two tools back the tiles a workbench DataX hub manifest names
 * (`source = "datax_support_requests"` / `"datax_api_health"`). Both emit the
 * Universal Result Contract view the tile renderer reads.
 *
 * Architecture: the gateway never touches Firestore. The SR gauntlet already
 * polls it every 15 minutes and publishes a cache of every SR (with SR2's
 * phase and needs-reply derivations) plus its investigation ledger; these
 * tools are pure mappers over those two files (executors/sr-gauntlet-state.ts).
 * The board is read-only: moving, closing and deleting tickets happens in
 * DataX SR2, which owns ticket state. The earlier move/delete/retriage actions
 * wrote to the retired sr_analyzer's private copy, never to DataX.
 */

import { catchError } from "../errors.js";
import { contract } from "../result.js";
import type { ToolDef, ToolResult } from "../types.js";
import {
  loadCache,
  loadLedger,
  type Ledger,
  type SrRecord,
} from "../executors/sr-gauntlet-state.js";

// SR2's canonical phase ids (datax lib/sr2/types.ts CANONICAL_PHASE_IDS). The
// cache carries phase ids only, not the srPhases docs with names and
// positions, so stages order as: open canonical phases, custom lanes
// (alphabetical), then the terminal phases, which are hidden by default —
// closed/archived SRs are noise on an ops board. `includeClosed` shows them.
const LEADING_PHASES = ["new", "engaged"];
const TERMINAL_PHASES = ["closed", "archive"];

// Per-column card cap — a TUI column can't usefully show hundreds of cards.
// Truncation is reported in meta (never silent). Override via `limit`.
const DEFAULT_COLUMN_LIMIT = 25;

// Firestore-reachability staleness thresholds for the API-Health tile. The
// signal is the gauntlet's last whole-collection read; its timer runs every
// 15 minutes, so these sit generously above that interval.
const FRESH_MS = 30 * 60 * 1000; // ≤30m since last sync ⇒ ok
const STALE_MS = 6 * 60 * 60 * 1000; // ≤6h ⇒ degraded; older/never ⇒ down

interface SrCard {
  id: string;
  kind: "sr";
  label: string;
  customer: string | null;
  service: string | null;
  opened: string;
  needsReply: boolean;
  investigatedAt: string | null;
  run: string | null;
}

function recordToCard(r: SrRecord, ledger: Ledger): SrCard {
  const led = ledger[r.id];
  return {
    id: r.id,
    kind: "sr",
    label: r.title,
    customer: r.submitterName,
    service: r.service,
    opened: r.createdAt,
    needsReply: r.needsReply,
    investigatedAt: led?.investigatedAt ?? null,
    run: led?.investigatedAt ? led.run : null,
  };
}

/** Column order for the phases present in the data. Exported for tests. */
export function orderPhases(present: Iterable<string>): string[] {
  const set = new Set(present);
  const custom = [...set]
    .filter((p) => !LEADING_PHASES.includes(p) && !TERMINAL_PHASES.includes(p))
    .sort();
  return [...LEADING_PHASES, ...custom, ...TERMINAL_PHASES].filter((p) => set.has(p));
}

const phaseTitle = (id: string): string => {
  const words = id.replace(/-/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
};

export function dataxTools(stateDir: string): ToolDef[] {
  return [
    {
      name: "datax_support_requests",
      description:
        "DataX support-request board (read-only). Every SR from the SR gauntlet's Firestore cache " +
        "(refreshed every 15 min) as a kanban grouped by SR2 phase (new, engaged, custom lanes), each " +
        "card flagged when it needs a reply and badged with the gauntlet's investigation date. " +
        "Closed/Archive hidden unless includeClosed. To move, close or delete a ticket, use DataX SR2.",
      inputSchema: {
        type: "object",
        properties: {
          includeClosed: {
            type: "boolean",
            description: "Include the Closed/Archive phases (default false).",
          },
          limit: {
            type: "number",
            description: `Max cards per column (default ${DEFAULT_COLUMN_LIMIT}).`,
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        const includeClosed = args.includeClosed === true;
        const limit =
          typeof args.limit === "number" && args.limit > 0
            ? Math.floor(args.limit)
            : DEFAULT_COLUMN_LIMIT;
        try {
          const [cache, ledger] = await Promise.all([loadCache(stateDir), loadLedger(stateDir)]);

          const phases = orderPhases(cache.records.map((r) => r.phase)).filter(
            (p) => includeClosed || !TERMINAL_PHASES.includes(p),
          );

          const truncated: Record<string, number> = {};
          let shown = 0;
          let investigated = 0;
          let needsReply = 0;

          const stages = phases.map((phase) => {
            const all = cache.records
              .filter((r) => r.phase === phase)
              .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
            const dropped = Math.max(0, all.length - limit);
            if (dropped > 0) truncated[phase] = dropped;
            const cards = all.slice(0, limit).map((r) => {
              const card = recordToCard(r, ledger);
              if (card.investigatedAt) investigated += 1;
              if (card.needsReply) needsReply += 1;
              shown += 1;
              return card;
            });
            return { id: phase, title: phaseTitle(phase), cards };
          });

          return {
            status: "ok",
            message: `${shown} SR(s) across ${stages.length} phase(s), ${needsReply} need a reply`,
            view: contract("kanban", "Support Requests", { stages }, {
              source: "sr_gauntlet:sr-cache",
              syncedAt: cache.syncedAt,
              totalTickets: cache.records.length,
              shownTickets: shown,
              investigatedTickets: investigated,
              needsReplyTickets: needsReply,
              includeClosed,
              ...(Object.keys(truncated).length > 0 && { truncated }),
            }),
          };
        } catch (err) {
          return catchError(
            "UNAVAILABLE",
            "Could not load the DataX support board from the SR gauntlet cache",
            err,
            `Check sr-gauntlet.service on this host and ${stateDir}/sr-cache.json.`,
          );
        }
      },
    },
    {
      name: "datax_api_health",
      description:
        "DataX backend health — Firestore reachability as last observed by the SR gauntlet's " +
        "15-minute poll. Fresh last sync ⇒ ok; stale ⇒ degraded; no recent sync or no cache ⇒ down. " +
        "Backs the DataX hub's API Health tile.",
      inputSchema: { type: "object", properties: {} },
      handler: async (): Promise<ToolResult> => {
        let status: "ok" | "degraded" | "down" = "down";
        let note = "no successful Firestore sync recorded";
        let syncedAt: string | null = null;

        try {
          const cache = await loadCache(stateDir);
          syncedAt = cache.syncedAt;
          if (syncedAt) {
            const ageMs = Date.now() - new Date(syncedAt).getTime();
            const ageMin = Math.round(ageMs / 60000);
            const detail = `${cache.records.length} SR(s) cached`;
            if (ageMs <= FRESH_MS) {
              status = "ok";
              note = `last sync ${ageMin}m ago — ${detail}`;
            } else if (ageMs <= STALE_MS) {
              status = "degraded";
              note = `last sync ${ageMin}m ago (stale) — ${detail}`;
            } else {
              note = `last sync ${ageMin}m ago (too old) — ${detail}`;
            }
          }
        } catch (err) {
          // Unreadable cache — render the tile "down" live rather than
          // erroring into the fixture fallback.
          note = `SR gauntlet cache unreadable: ${err instanceof Error ? err.message : String(err)}`;
        }

        const checks = [
          { name: "firestore (sr gauntlet poll)", status, latency_ms: null, note },
        ];

        return {
          status: "ok",
          message: `DataX API health: ${status}`,
          view: contract("status", "API Health", { overall: status, checks }, {
            source: "sr_gauntlet:sr-cache",
            lastRunAt: syncedAt,
          }),
        };
      },
    },
  ];
}
