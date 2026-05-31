/**
 * hwc_notify — MCP wrapper over the local hwc-notify HTTP service.
 *
 * Single consolidated tool with an `action` field (mirrors
 * n8n-consolidation.ts). Talks to http://127.0.0.1:11600 — the loopback
 * service binds there per the NixOS module's bindAddr/port options.
 * Both MCP and the hwc-notify service run on hwc-server, so this is an
 * in-host call.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { mcpError } from "../errors.js";

const NOTIFY_BASE = "http://127.0.0.1:11600";

const ACTIONS = ["send", "recent", "status", "health"] as const;
type Action = (typeof ACTIONS)[number];

const HWC_NOTIFY_SCHEMA = {
  type: "object",
  properties: {
    action: {
      type: "string",
      enum: [...ACTIONS],
      description:
        "send: dispatch a Notification (topic + title required). " +
        "recent: page the audit log (optional filters). " +
        "status: per-channel circuit-breaker state. " +
        "health: liveness + wired channel list.",
    },
    // send args
    topic: {
      type: "string",
      description:
        "[send] Routing topic — lowercase kebab-case slug. Matches notification.topic against routes in parts/routes.nix.",
    },
    title: {
      type: "string",
      description: "[send] Short headline (Discord embed title, email subject).",
    },
    body: {
      type: "string",
      description: "[send] Body text. Defaults to empty.",
    },
    priority: {
      type: "integer",
      minimum: 1,
      maximum: 5,
      default: 3,
      description: "[send] 1=critical, 2=high, 3=warn, 4=info, 5=low.",
    },
    source: {
      type: "string",
      description: '[send] Origin label. Defaults to "mcp".',
    },
    tags: {
      type: "array",
      items: { type: "string" },
      description: "[send] Tag list shown alongside the notification.",
    },
    // recent args
    limit: {
      type: "integer",
      minimum: 1,
      maximum: 500,
      default: 50,
      description: "[recent] Max rows.",
    },
    filter_topic: {
      type: "string",
      description: "[recent] Filter to a single topic.",
    },
    filter_source: {
      type: "string",
      description: "[recent] Filter to a single source.",
    },
    filter_status: {
      type: "string",
      enum: ["ok", "failed"],
      description:
        '[recent] Filter to fully-successful or any-failed dispatches. Omit for "any".',
    },
  },
  required: ["action"],
};

async function httpGet(path: string): Promise<unknown> {
  const res = await fetch(`${NOTIFY_BASE}${path}`);
  if (!res.ok) {
    throw new Error(`GET ${path} → HTTP ${res.status}`);
  }
  return res.json();
}

async function httpPost(path: string, body: unknown): Promise<unknown> {
  const res = await fetch(`${NOTIFY_BASE}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  // Even 207/502 from /notify are still application/json with a
  // structured DispatchResult — surface them as data, not errors.
  const data = await res.json().catch(() => null);
  return { httpStatus: res.status, data };
}

export function notifyTools(): ToolDef[] {
  return [
    {
      name: "hwc_notify",
      description:
        "Notification dispatcher. Single tool, action-dispatched. Use send to fire " +
        "an alert/lead/info notification (routed through parts/routes.nix to Discord + " +
        "SMTP), recent to query the audit log, status for circuit-breaker state, health " +
        "for liveness. All calls go to http://127.0.0.1:11600 on hwc-server.",
      inputSchema: HWC_NOTIFY_SCHEMA,
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
            case "send": {
              const topic = String(args.topic ?? "");
              const title = String(args.title ?? "");
              if (!topic) {
                return mcpError({ type: "VALIDATION_ERROR", message: "send: topic is required" });
              }
              if (!title) {
                return mcpError({ type: "VALIDATION_ERROR", message: "send: title is required" });
              }
              const payload: Record<string, unknown> = {
                topic,
                title,
                body: String(args.body ?? ""),
                priority: typeof args.priority === "number" ? args.priority : 3,
                source: String(args.source ?? "mcp"),
              };
              if (Array.isArray(args.tags)) {
                payload.tags = args.tags
                  .filter((t): t is string => typeof t === "string")
                  .filter((t) => t.length > 0);
              }
              const result = await httpPost("/notify", payload);
              return { status: "ok", message: "notification dispatched", data: result };
            }
            case "recent": {
              const params = new URLSearchParams();
              const limit = typeof args.limit === "number" ? args.limit : 50;
              params.set("limit", String(limit));
              if (typeof args.filter_topic === "string" && args.filter_topic) {
                params.set("topic", args.filter_topic);
              }
              if (typeof args.filter_source === "string" && args.filter_source) {
                params.set("source", args.filter_source);
              }
              if (args.filter_status === "ok" || args.filter_status === "failed") {
                params.set("status", args.filter_status);
              }
              const data = await httpGet(`/audit/recent?${params.toString()}`);
              return { status: "ok", message: "audit query ok", data };
            }
            case "status": {
              const data = await httpGet("/circuit/status");
              return { status: "ok", message: "circuit status", data };
            }
            case "health": {
              const data = await httpGet("/health");
              return { status: "ok", message: "health ok", data };
            }
          }
        } catch (err) {
          return mcpError({
            type: "INTERNAL_ERROR",
            message: `hwc_notify ${action} failed`,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      },
    },
  ];
}
