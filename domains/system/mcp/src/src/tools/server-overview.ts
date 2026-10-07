/**
 * hwc_server_overview — one kanban over the six host status tools.
 *
 * A composite read for the workbench Server hub: it calls hwc_services,
 * hwc_storage_status, hwc_monitoring, hwc_media_status, hwc_network and
 * hwc_build_git_status in parallel (each bounded by its own timeout), then
 * puts every non-healthy check AND every failed read in "Needs you" and the
 * healthy checks in one stage per system. A failed read is a card naming the
 * tool and a code — never a silently empty stage.
 *
 * Load bounds on the shared gateway: the composed result is cached for 30 s,
 * concurrent cold reads share one fan-out (single-flight), and `fresh=true`
 * (the workbench's manual refresh) skips the cache but still joins an
 * in-flight read. The sub-tools are resolved from the registry at the
 * composition root (tools/index.ts), so this module owns no status logic.
 */

import type { McpErrorType, ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";

/** The six status reads, in board order. `system` titles the healthy stage. */
export const OVERVIEW_SOURCES = [
  { tool: "hwc_services", params: { action: "status" }, system: "Services" },
  { tool: "hwc_storage_status", params: {}, system: "Storage" },
  { tool: "hwc_monitoring", params: { action: "health" }, system: "Monitoring" },
  { tool: "hwc_media_status", params: {}, system: "Media" },
  { tool: "hwc_network", params: { action: "tunnels" }, system: "Network" },
  { tool: "hwc_build_git_status", params: {}, system: "NixOS Git" },
] as const;

/** The status tools' own vocabulary (workbench widgets._STATUS_GLYPH): ok/up are healthy. */
const HEALTHY = new Set(["ok", "up"]);
const KNOWN_STATUS = new Set(["ok", "up", "warning", "degraded", "down", "error"]);

/** Why a sub-read produced no trustworthy checks. Gateway codes plus three of ours. */
export type OverviewFailure = McpErrorType | "PARTIAL" | "NO_VIEW" | "MALFORMED";

interface Check {
  status: string;
  name: string;
  note?: string;
  latency_ms?: number;
}

export interface OverviewOptions {
  cacheMs?: number;
  timeoutMs?: number;
  now?: () => number;
}

type Source = (typeof OVERVIEW_SOURCES)[number];

/** Parse a status view's checks at the boundary; null when the shape is wrong. */
function parseChecks(view: unknown): Check[] | null {
  if (!view || typeof view !== "object") return null;
  const v = view as { kind?: unknown; data?: unknown };
  if (v.kind !== "status" || !v.data || typeof v.data !== "object") return null;
  const checks = (v.data as { checks?: unknown }).checks;
  if (!Array.isArray(checks)) return null;
  const out: Check[] = [];
  for (const c of checks) {
    if (!c || typeof c !== "object") return null;
    const r = c as Record<string, unknown>;
    if (typeof r.status !== "string" || !KNOWN_STATUS.has(r.status) || typeof r.name !== "string") return null;
    out.push({
      status: r.status,
      name: r.name,
      note: typeof r.note === "string" ? r.note : undefined,
      latency_ms: typeof r.latency_ms === "number" ? r.latency_ms : undefined,
    });
  }
  return out;
}

function checkCard(src: Source, check: Check) {
  const healthy = HEALTHY.has(check.status);
  const facts: [string, string][] = [["system", src.system], ["status", check.status]];
  if (check.latency_ms !== undefined) facts.push(["latency", `${check.latency_ms} ms`]);
  facts.push(["tool", src.tool]);
  return {
    id: `${src.tool}:${check.name}`,
    kind: "check",
    label: `${src.system}: ${check.name}`,
    tag: check.status,
    reason: check.note || check.status,
    system: src.system,
    status: check.status,
    priority: healthy ? "low" : check.status === "down" || check.status === "error" ? "critical" : "high",
    facts,
  };
}

function failureCard(src: Source, code: OverviewFailure, detail: string) {
  return {
    id: `${src.tool}:read`,
    kind: "check",
    label: `${src.system}: read failed`,
    tag: "error",
    reason: `${src.tool} ${code}: ${detail}`.slice(0, 200),
    system: src.system,
    status: "error",
    priority: "critical",
    facts: [["tool", src.tool], ["code", code], ["error", detail.slice(0, 200)]] as [string, string][],
  };
}

type Card = ReturnType<typeof checkCard> | ReturnType<typeof failureCard>;

/** Bound one sub-read; a timeout resolves to a coded failure, never a hang. */
function withTimeout(p: Promise<ToolResult>, ms: number): Promise<ToolResult | "TIMEOUT"> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<"TIMEOUT">((resolve) => {
    timer = setTimeout(() => resolve("TIMEOUT"), ms);
  });
  return Promise.race([p, timeout]).finally(() => clearTimeout(timer));
}

/** One sub-read → its cards. Every failure shape becomes a Needs-you card. */
async function readSource(src: Source, tools: Map<string, ToolDef>, timeoutMs: number): Promise<Card[]> {
  const def = tools.get(src.tool);
  if (!def) return [failureCard(src, "NOT_FOUND", "tool is not registered in this gateway")];
  let result: ToolResult | "TIMEOUT";
  try {
    result = await withTimeout(def.handler({ ...src.params }), timeoutMs);
  } catch (err) {
    return [failureCard(src, "INTERNAL_ERROR", err instanceof Error ? err.message : String(err))];
  }
  if (result === "TIMEOUT") return [failureCard(src, "TIMEOUT", `no answer within ${timeoutMs} ms`)];
  if (result.status === "error") {
    return [failureCard(src, result.error_type ?? "COMMAND_FAILED", result.message || "error without message")];
  }
  if (!result.view) return [failureCard(src, "NO_VIEW", "the tool returned no status view")];
  const checks = parseChecks(result.view);
  if (checks === null) return [failureCard(src, "MALFORMED", "the status view has an unexpected shape")];
  const cards: Card[] = checks.map((c) => checkCard(src, c));
  if (result.status === "partial") cards.unshift(failureCard(src, "PARTIAL", result.message || "partial result"));
  return cards;
}

interface Composed {
  columns: { id: string; title: string; cards: Card[] }[];
  needsYou: number;
  elapsedMs: number;
}

async function compose(tools: Map<string, ToolDef>, timeoutMs: number, now: () => number): Promise<Composed> {
  const started = now();
  const perSource = await Promise.all(OVERVIEW_SOURCES.map((src) => readSource(src, tools, timeoutMs)));
  const needs: Card[] = [];
  const columns: Composed["columns"] = [];
  OVERVIEW_SOURCES.forEach((src, i) => {
    const healthy: Card[] = [];
    for (const card of perSource[i]) (HEALTHY.has(card.status) ? healthy : needs).push(card);
    columns.push({ id: src.tool, title: src.system, cards: healthy });
  });
  return {
    columns: [{ id: "needs-you", title: "Needs you", cards: needs }, ...columns],
    needsYou: needs.length,
    elapsedMs: now() - started,
  };
}

/** Build the tool over the registry's status tools (resolved by name). */
export function serverOverviewTool(registry: ToolDef[], opts: OverviewOptions = {}): ToolDef {
  const cacheMs = opts.cacheMs ?? 30_000;
  const timeoutMs = opts.timeoutMs ?? 4_000;
  const now = opts.now ?? Date.now;
  const tools = new Map(registry.map((t) => [t.name, t]));
  let cached: { at: number; value: Composed } | null = null;
  let inflight: Promise<Composed> | null = null;

  const read = (): Promise<Composed> => {
    // Single-flight: every caller during a fan-out shares it.
    if (!inflight) {
      inflight = compose(tools, timeoutMs, now)
        .then((value) => {
          cached = { at: now(), value };
          return value;
        })
        .finally(() => {
          inflight = null;
        });
    }
    return inflight;
  };

  return {
    name: "hwc_server_overview",
    description:
      "One kanban over the six host status tools (services, storage, monitoring, media, network, " +
      "nixos git). 'Needs you' holds every non-ok check and every failed read (a card naming the " +
      "tool and an error code); healthy checks sit in one stage per system. Sub-reads run in " +
      "parallel with a 4 s timeout each; the result is cached 30 s — pass fresh=true to skip the cache.",
    inputSchema: {
      type: "object",
      properties: {
        fresh: { type: "boolean", description: "Skip the 30 s cache (a manual refresh)" },
      },
    },
    handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
      const fresh = args["fresh"] === true;
      const hit = !fresh && cached !== null && now() - cached.at < cacheMs;
      const value = hit ? cached!.value : await read();
      return {
        status: "ok",
        message: value.needsYou === 0
          ? "Server: all checks healthy"
          : `Server: ${value.needsYou} check(s) need you`,
        data: { needsYou: value.needsYou },
        view: contract("kanban", "Server", { columns: value.columns }, {
          source: "hwc_server_overview",
          cached: hit,
          elapsed_ms: value.elapsedMs,
        }),
      };
    },
  };
}
