/**
 * datax_* — DataX support + service health for the workbench DataX hub.
 *
 * These two tools back the tiles in workbench's `hubs/datax.toml`
 * (`source = "datax_support_requests"` / `"datax_api_health"`). Until they
 * existed the gateway had no datax_* tool, so every call missed and the hub
 * silently rendered fixtures. Both emit the Universal Result Contract view the
 * tile renderer reads.
 *
 * Architecture: the gateway never touches Firestore. sr_analyzer (the running
 * SR board service) owns the Firestore poll + phase model; the gauntlet ledger
 * owns investigation state. These tools are pure mappers over those two ports
 * (see executors/sr-analyzer.ts + executors/sr-gauntlet-ledger.ts).
 */

import { catchError, mcpError } from "../errors.js";
import { contract } from "../result.js";
import type { ToolDef, ToolResult } from "../types.js";
import {
  fetchBoard,
  fetchImportStatus,
  moveTicket,
  deleteTicket,
  triageAll,
  type AnalyzerTicket,
} from "../executors/sr-analyzer.js";
import { loadLedger } from "../executors/sr-gauntlet-ledger.js";

// Canonical phases the SR tile hides by default — closed/archived SRs are noise
// on an ops board. `includeClosed: true` brings them back. Matched on phase
// name, case-insensitive (sr_analyzer's CANONICAL_PHASES).
const HIDDEN_PHASES = new Set(["closed", "archive"]);

// Per-column card cap — a TUI column can't usefully show hundreds of cards.
// Truncation is reported in meta (never silent). Override via `limit`.
const DEFAULT_COLUMN_LIMIT = 25;

// Firestore-reachability staleness thresholds for the API-Health tile. The
// signal is sr_analyzer's last successful import; a fresh run means the poller
// read Firestore recently. Tuned generously above the poller's own interval.
const FRESH_MS = 30 * 60 * 1000; // ≤30m since last sync ⇒ ok
const STALE_MS = 6 * 60 * 60 * 1000; // ≤6h ⇒ degraded; older/never ⇒ down

interface SrCard {
  id: string;
  kind: "sr";
  label: string;
  customer: string | null;
  priority: string;
  opened: string;
  needsReply: boolean;
  externalId: string | null;
  investigatedAt: string | null;
  run: string | null;
}

function ticketToCard(
  t: AnalyzerTicket,
  ledger: Record<string, { investigatedAt: string; run: string }>,
): SrCard {
  const led = t.externalId ? ledger[t.externalId] : undefined;
  return {
    id: t.id,
    kind: "sr",
    label: t.title,
    customer: t.submitterName,
    priority: t.priority,
    opened: t.createdAt,
    needsReply: t.needsReply,
    externalId: t.externalId,
    investigatedAt: led?.investigatedAt ?? null,
    run: led?.run ?? null,
  };
}

export function dataxTools(analyzerUrl: string, ledgerPath: string): ToolDef[] {
  return [
    {
      name: "datax_support_requests",
      description:
        "DataX support-request board (Triage Surface Contract). READ (default action=board): live tickets " +
        "from sr_analyzer as a kanban grouped by phase (New/Open/…), each card badged with the SR gauntlet's " +
        "investigation date when auto-investigated; Closed/Archive phases hidden unless includeClosed. " +
        "WRITES: action=move with id+target=<phase id> moves a ticket between phases (the kanban column " +
        "move); action=delete with id removes a ticket; action=retriage re-runs the analyzer's own triage " +
        "pass over all tickets. Backs the workbench DataX hub.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["board", "move", "delete", "retriage"],
            default: "board",
            description: "board = read; move (id+target) / delete (id) / retriage = writes",
          },
          id: {
            type: "string",
            description: "[move/delete] ticket id (the kanban card id)",
          },
          target: {
            type: "string",
            description: "[move] destination phase id (the kanban column id)",
          },
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
        const action = (args.action as string) || "board";

        // ── writes: the generic workbench card_actions/board_actions path ──
        if (action !== "board") {
          try {
            if (action === "retriage") {
              const result = await triageAll(analyzerUrl);
              return {
                status: "ok",
                message: "sr_analyzer triage pass re-run over all tickets",
                data: { action, result },
              };
            }
            const id = String(args.id ?? "").trim();
            if (!id) {
              return mcpError({
                type: "VALIDATION_ERROR",
                message: `write '${action}' needs a ticket id`,
                suggestion: "Pass the kanban card id as `id`",
              });
            }
            if (action === "move") {
              const target = String(args.target ?? "").trim();
              if (!target) {
                return mcpError({
                  type: "VALIDATION_ERROR",
                  message: "move needs target=<phase id> (the kanban column id)",
                });
              }
              const result = await moveTicket(analyzerUrl, id, target);
              return { status: "ok", message: `moved ${id} → phase ${target}`, data: { action, id, target, result } };
            }
            if (action === "delete") {
              await deleteTicket(analyzerUrl, id);
              return { status: "ok", message: `deleted ticket ${id}`, data: { action, id } };
            }
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `unknown action "${action}"`,
            });
          } catch (err) {
            return catchError(
              "NETWORK_ERROR",
              `sr_analyzer ${action} failed`,
              err,
              `Check the sr_analyzer container is up at ${analyzerUrl}.`,
            );
          }
        }

        // ── read: the kanban board ──
        const includeClosed = args.includeClosed === true;
        const limit =
          typeof args.limit === "number" && args.limit > 0
            ? Math.floor(args.limit)
            : DEFAULT_COLUMN_LIMIT;
        try {
          const [board, ledger] = await Promise.all([
            fetchBoard(analyzerUrl),
            loadLedger(ledgerPath),
          ]);

          const phases = [...board.phases]
            .sort((a, b) => a.position - b.position)
            .filter((p) => includeClosed || !HIDDEN_PHASES.has(p.name.toLowerCase()));

          const truncated: Record<string, number> = {};
          let shown = 0;
          let investigated = 0;

          const columns = phases.map((phase) => {
            const all = board.tickets
              .filter((t) => t.phaseId === phase.id)
              .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
            const dropped = Math.max(0, all.length - limit);
            if (dropped > 0) truncated[phase.name] = dropped;
            const cards = all.slice(0, limit).map((t) => {
              const card = ticketToCard(t, ledger);
              if (card.investigatedAt) investigated += 1;
              shown += 1;
              return card;
            });
            return { id: phase.id, title: phase.name, cards };
          });

          return {
            status: "ok",
            message: `${shown} SR(s) across ${columns.length} phase(s)`,
            view: contract("kanban", "Support Requests", { columns }, {
              source: "sr_analyzer",
              analyzerUrl,
              totalTickets: board.tickets.length,
              shownTickets: shown,
              investigatedTickets: investigated,
              includeClosed,
              ...(Object.keys(truncated).length > 0 && { truncated }),
            }),
          };
        } catch (err) {
          return catchError(
            "NETWORK_ERROR",
            "Could not load DataX support board from sr_analyzer",
            err,
            `Check the sr_analyzer container is up at ${analyzerUrl} (GET /api/board).`,
          );
        }
      },
    },
    {
      name: "datax_api_health",
      description:
        "DataX backend health — Firestore reachability as last observed by " +
        "sr_analyzer's import poller. Fresh last-sync ⇒ ok; stale ⇒ degraded; " +
        "no recent sync (or poller unreachable) ⇒ down. Backs the DataX hub's " +
        "API Health tile.",
      inputSchema: { type: "object", properties: {} },
      handler: async (): Promise<ToolResult> => {
        let status: "ok" | "degraded" | "down" = "down";
        let note = "no successful Firestore sync recorded";
        let lastRunAt: string | null = null;

        try {
          const imp = await fetchImportStatus(analyzerUrl);
          lastRunAt = imp.lastRunAt;
          if (imp.lastRunAt) {
            const ageMs = Date.now() - new Date(imp.lastRunAt).getTime();
            const ageMin = Math.round(ageMs / 60000);
            const res = imp.lastResult;
            const detail = res
              ? `${res.candidates} candidate(s), ${res.updated} updated`
              : "no result detail";
            if (ageMs <= FRESH_MS) {
              status = "ok";
              note = `last sync ${ageMin}m ago — ${detail}`;
            } else if (ageMs <= STALE_MS) {
              status = "degraded";
              note = `last sync ${ageMin}m ago (stale) — ${detail}`;
            } else {
              status = "down";
              note = `last sync ${ageMin}m ago (too old) — ${detail}`;
            }
          }
        } catch (err) {
          // sr_analyzer (the poller) itself is unreachable — render the tile
          // "down" live rather than erroring into the fixture fallback.
          status = "down";
          note = `sr_analyzer poller unreachable: ${
            err instanceof Error ? err.message : String(err)
          }`;
        }

        const checks = [
          { name: "firestore (datax import)", status, latency_ms: null, note },
        ];
        const overall = status;

        return {
          status: "ok",
          message: `DataX API health: ${overall}`,
          view: contract("status", "API Health", { overall, checks }, {
            source: "sr_analyzer:import-status",
            lastRunAt,
          }),
        };
      },
    },
  ];
}
