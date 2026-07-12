/**
 * hwc_leads — MCP wrapper over the local hwc-leads HTTP service.
 *
 * Single consolidated tool with an `action` field (mirrors
 * hwc-notify's notify.ts). Talks to http://127.0.0.1:11650.
 * Both MCP gateway and hwc-leads run on hwc-server, so this is an
 * in-host loopback call.
 *
 * Actions all touch read or idempotent endpoints — no `send` because
 * lead submission requires HMAC-signed payloads from the calc/contact
 * forms, not operator-initiated chat actions.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { mcpError } from "../errors.js";
import { contract } from "../result.js";

const LEADS_BASE = "http://127.0.0.1:11650";

const ACTIONS = ["recent", "get", "replay", "health"] as const;
type Action = (typeof ACTIONS)[number];

const HWC_LEADS_SCHEMA = {
  type: "object",
  properties: {
    action: {
      type: "string",
      enum: [...ACTIONS],
      description:
        "recent: paged lead list. " +
        "get: fetch one lead by id. " +
        "replay: idempotently resume JT graph creation on a pending_jt row. " +
        "health: liveness + wired downstreams.",
    },
    // recent
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 500,
      default: 50,
      description: "[recent] Max rows.",
    },
    filter_source: {
      type: "string",
      enum: ["contact", "calculator", "appointment"],
      description: "[recent] Filter to a single source.",
    },
    filter_status: {
      type: "string",
      enum: ["received", "validated", "pending_jt", "complete", "failed"],
      description: "[recent] Filter to a single status.",
    },
    // get / replay
    lead_id: {
      type: "string",
      description:
        "[get / replay] UUID of the lead. Pulled from a previous `recent` call or from POST /leads' response.",
    },
  },
  required: ["action"],
};

async function httpGet(path: string): Promise<unknown> {
  const res = await fetch(`${LEADS_BASE}${path}`);
  if (!res.ok && res.status !== 404) {
    const body = await res.text().catch(() => "");
    throw new Error(`GET ${path} → HTTP ${res.status}: ${body.slice(0, 200)}`);
  }
  return { httpStatus: res.status, data: await res.json().catch(() => null) };
}

async function httpPost(path: string): Promise<unknown> {
  const res = await fetch(`${LEADS_BASE}${path}`, { method: "POST" });
  const data = await res.json().catch(() => null);
  return { httpStatus: res.status, data };
}

export function leadsTools(): ToolDef[] {
  return [
    {
      name: "hwc_leads",
      description:
        "Lead pipeline introspection + recovery. recent / get / replay / health. " +
        "Loopback call to http://127.0.0.1:11650 on hwc-server. Submitting a new " +
        "lead is NOT an operator action — those come from the website forms and " +
        "require HMAC. Use `replay` to resume a row whose JT graph creation " +
        "landed at pending_jt (idempotent on whatever JT ids the row already has).",
      inputSchema: HWC_LEADS_SCHEMA,
      handler: async (args): Promise<ToolResult> => {
        const action = String(args.action ?? "") as Action;
        if (!ACTIONS.includes(action)) {
          return mcpError({
            type: "VALIDATION_ERROR",
            message: `unknown action "${args.action}". valid: ${ACTIONS.join(" | ")}`,
          });
        }

        try {
          switch (action) {
            case "recent": {
              const params = new URLSearchParams();
              const limit = typeof args.limit === "number" ? args.limit : 50;
              params.set("limit", String(limit));
              if (typeof args.filter_source === "string" && args.filter_source) {
                params.set("source", args.filter_source);
              }
              if (typeof args.filter_status === "string" && args.filter_status) {
                params.set("status", args.filter_status);
              }
              const data = await httpGet(`/leads/recent?${params.toString()}`) as {
                httpStatus?: number;
                data?: {
                  count?: number;
                  rows?: Array<{
                    id?: string;
                    status?: string;
                    payload?: {
                      source?: string;
                      contact?: { name?: string };
                      calc?: { estimate?: { low?: number; high?: number } };
                    };
                  }>;
                };
              };
              const leadRows = data?.data?.rows ?? [];
              const fmtEstimate = (e?: { low?: number; high?: number }): string =>
                e && typeof e.low === "number" && typeof e.high === "number"
                  ? `$${Math.round(e.low / 1000)}k–${Math.round(e.high / 1000)}k`
                  : "";
              // Source CLASS prefix — same vocabulary as hwc-crm's board.py:
              // inbound (came to us: form/call/referral) vs scouted (we found
              // them: lead_scout ingest). hwc.leads holds BOTH once the CRM
              // ingest promotes scraped leads, so an unclassed Source column
              // silently blurs the two populations.
              const INBOUND = new Set(["contact", "calculator", "appointment", "phone", "referral", "website"]);
              const SCOUTED = new Set(["facebook_scrape", "network_scrape"]);
              const classedSource = (s: string): string =>
                INBOUND.has(s) ? `inbound · ${s}` : SCOUTED.has(s) ? `scouted · ${s}` : s;
              const crmUiBase = (process.env.HWC_CRM_UI_URL || "https://crm.hwc.iheartwoodcraft.com").replace(/\/$/, "");
              return {
                status: "ok",
                message: "recent leads",
                data,
                // Universal Result Contract view (table): flatten the lead
                // service's nested rows into column-keyed cells the renderer
                // reads via row[col]; id/kind make each row a selectable entity.
                view: contract("table", "Leads", {
                  columns: ["Name", "Source", "Estimate", "Status"],
                  rows: leadRows.map((r) => ({
                    kind: "lead",
                    id: r.id ?? "",
                    Name: r.payload?.contact?.name ?? "",
                    Source: classedSource(r.payload?.source ?? ""),
                    Estimate: fmtEstimate(r.payload?.calc?.estimate),
                    Status: r.status ?? "",
                    // Non-column extra: rides into the row's entity data bag —
                    // the CRM drawer deep link for click-to-action surfaces.
                    url: r.id ? `${crmUiBase}/?lead=${r.id}` : "",
                  })),
                }, { count: data?.data?.count ?? leadRows.length, httpStatus: data?.httpStatus, source: "hwc_leads" }),
              };
            }
            case "get": {
              const leadId = String(args.lead_id ?? "");
              if (!leadId) {
                return mcpError({ type: "VALIDATION_ERROR", message: "get: lead_id is required" });
              }
              const data = await httpGet(`/leads/${leadId}`);
              return { status: "ok", message: "lead", data };
            }
            case "replay": {
              const leadId = String(args.lead_id ?? "");
              if (!leadId) {
                return mcpError({ type: "VALIDATION_ERROR", message: "replay: lead_id is required" });
              }
              const data = await httpPost(`/leads/${leadId}/replay`);
              return { status: "ok", message: "replay attempted", data };
            }
            case "health": {
              const data = await httpGet("/health");
              return { status: "ok", message: "health ok", data };
            }
          }
        } catch (err) {
          return mcpError({
            type: "INTERNAL_ERROR",
            message: `hwc_leads ${action} failed`,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      },
    },
  ];
}
