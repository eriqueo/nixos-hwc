/**
 * n8n-mcp consolidation — maps 21 raw n8n tools → 4 consolidated tools.
 *
 * Consolidated tools:
 *   n8n_workflows      — list, get, create, update, update_partial, delete, autofix, search_nodes
 *   n8n_templates      — search, deploy
 *   n8n_validate       — by_id, by_object, node
 *   n8n_workflow_status — composite snapshot (get + executions + versions)
 *
 * Pass-through (not consolidated):
 *   n8n_executions, n8n_test_workflow, n8n_workflow_versions,
 *   n8n_manage_datatable, n8n_health_check
 */

import type { ToolDef, ToolResult } from "./types.js";
import type { ConsolidateFn, BackendCallFn, ConsolidationResult } from "./backend-manager.js";
import type { DiscoveredTool } from "./stdio-backend.js";

/* ═══════════════════════════════════════════════════════════════════ */
/*  Helper                                                             */
/* ═══════════════════════════════════════════════════════════════════ */

/** Parse a raw backend content response into typed data */
function parseBackend(r: {
  content: Array<{ type: string; text: string }>;
  isError?: boolean;
}): { ok: boolean; data: unknown; rawText: string } {
  const rawText = r.content[0]?.text ?? "";
  try {
    const data = JSON.parse(rawText) as unknown;
    return { ok: !r.isError, data, rawText };
  } catch {
    return { ok: !r.isError, data: rawText, rawText };
  }
}

/** Safely extract a string from unknown data, at a given key path */
function safeStr(obj: unknown, key: string): string {
  if (obj && typeof obj === "object" && key in (obj as Record<string, unknown>)) {
    const val = (obj as Record<string, unknown>)[key];
    return val !== null && val !== undefined ? String(val) : "";
  }
  return "";
}

function safeNum(obj: unknown, key: string): number | undefined {
  if (obj && typeof obj === "object" && key in (obj as Record<string, unknown>)) {
    const val = (obj as Record<string, unknown>)[key];
    if (typeof val === "number") return val;
    if (typeof val === "string") {
      const n = Number(val);
      if (!isNaN(n)) return n;
    }
  }
  return undefined;
}

/** Unwrap n8n-mcp's {success, data: {...}} envelope if present */
function unwrap(data: unknown): unknown {
  if (data && typeof data === "object" && "data" in (data as Record<string, unknown>)) {
    return (data as Record<string, unknown>).data;
  }
  return data;
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  n8n_workflows                                                      */
/* ═══════════════════════════════════════════════════════════════════ */

const N8N_WORKFLOWS_SCHEMA: Record<string, unknown> = {
  type: "object",
  properties: {
    action: {
      type: "string",
      enum: ["list", "get", "create", "update", "update_partial", "delete", "autofix", "search_nodes"],
      description: "The operation to perform.",
    },
    // get
    workflowId: { type: "string", description: "Workflow ID (required for: get, update, update_partial, delete, autofix)." },
    detail: { type: "string", enum: ["summary", "full"], description: "For action=get: 'summary' (default) or 'full'." },
    // create / update
    workflow: { type: "object", description: "Workflow object (required for: create, update)." },
    // update_partial
    updates: { type: "object", description: "Partial update fields (required for: update_partial)." },
    // search_nodes
    query: { type: "string", description: "Search query (required for: search_nodes)." },
    // list filters
    active: { type: "boolean", description: "Filter by active state (optional, for: list)." },
    tags: { type: "array", items: { type: "string" }, description: "Filter by tags (optional, for: list)." },
    // format
    format: { type: "string", enum: ["text", "json"], description: "Output format (default: text)." },
  },
  required: ["action"],
};

function formatWorkflowSummary(wf: Record<string, unknown>): string {
  const id = safeStr(wf, "id");
  const name = safeStr(wf, "name");
  const active = String(wf.active ?? "?");
  const nodeCount = safeNum(wf, "nodeCount") ?? (Array.isArray(wf.nodes) ? (wf.nodes as unknown[]).length : "?");
  const triggerType = safeStr(wf, "triggerType") || "unknown";
  return `id:${id} | name:${name} | active:${active} | nodes:${nodeCount} | trigger:${triggerType}`;
}

function formatWorkflowGetSummary(wf: Record<string, unknown>): string {
  const name = safeStr(wf, "name");
  const active = String(wf.active ?? "?");
  const triggerType = safeStr(wf, "triggerType") || "unknown";
  const nodeCount = safeNum(wf, "nodeCount") ?? (Array.isArray(wf.nodes) ? (wf.nodes as unknown[]).length : "?");
  const updatedAt = safeStr(wf, "updatedAt");
  return `name:${name} | active:${active} | trigger:${triggerType} | nodes:${nodeCount} | updated:${updatedAt}`;
}

function buildN8nWorkflows(call: BackendCallFn): ToolDef {
  return {
    name: "n8n_workflows",
    description:
      "Workflow management. Use action=search_nodes to find nodes by type. " +
      "action=get with detail=summary (default) returns name/active/trigger/nodeCount only; detail=full returns full workflow JSON. " +
      "Actions: list, get, create, update, update_partial, delete, autofix, search_nodes.",
    inputSchema: N8N_WORKFLOWS_SCHEMA,
    handler: async (args): Promise<ToolResult> => {
      const action = String(args.action ?? "");
      const fmt = String(args.format ?? "text");

      switch (action) {
        case "list": {
          const callArgs: Record<string, unknown> = {};
          if (args.active !== undefined) callArgs.active = args.active;
          if (args.tags !== undefined) callArgs.tags = args.tags;
          const r = parseBackend(await call("n8n_list_workflows", callArgs));
          if (!r.ok) return { status: "error", message: `n8n_list_workflows failed: ${r.rawText}` };
          const inner = unwrap(r.data);
          if (fmt === "json") return { status: "ok", message: "Workflows listed.", data: inner };
          // Text format
          const wfData = inner as Record<string, unknown>;
          const workflows = (wfData?.workflows ?? wfData) as Array<Record<string, unknown>>;
          const lines = Array.isArray(workflows)
            ? workflows.map(formatWorkflowSummary)
            : [JSON.stringify(inner)];
          return { status: "ok", message: `${lines.length} workflow(s).\n${lines.join("\n")}` };
        }

        case "get": {
          const workflowId = String(args.workflowId ?? "");
          if (!workflowId) return { status: "error", message: "workflowId is required for action=get." };
          const detail = String(args.detail ?? "summary");
          const r = parseBackend(await call("n8n_get_workflow", { id: workflowId }));
          if (!r.ok) return { status: "error", message: `n8n_get_workflow failed: ${r.rawText}` };
          const inner = unwrap(r.data) as Record<string, unknown>;
          if (detail === "full" || fmt === "json") {
            return { status: "ok", message: "Workflow retrieved.", data: inner };
          }
          // Summary text
          const summary = formatWorkflowGetSummary(inner ?? {});
          return { status: "ok", message: summary };
        }

        case "create": {
          if (!args.workflow) return { status: "error", message: "workflow object is required for action=create." };
          const r = parseBackend(await call("n8n_create_workflow", { workflow: args.workflow }));
          if (!r.ok) return { status: "error", message: `n8n_create_workflow failed: ${r.rawText}` };
          return { status: "ok", message: "Workflow created.", data: unwrap(r.data) };
        }

        case "update": {
          if (!args.workflowId) return { status: "error", message: "workflowId is required for action=update." };
          if (!args.workflow) return { status: "error", message: "workflow object is required for action=update." };
          const r = parseBackend(await call("n8n_update_full_workflow", { id: args.workflowId, workflow: args.workflow }));
          if (!r.ok) return { status: "error", message: `n8n_update_full_workflow failed: ${r.rawText}` };
          return { status: "ok", message: "Workflow updated.", data: unwrap(r.data) };
        }

        case "update_partial": {
          if (!args.workflowId) return { status: "error", message: "workflowId is required for action=update_partial." };
          if (!args.updates) return { status: "error", message: "updates object is required for action=update_partial." };
          const r = parseBackend(await call("n8n_update_partial_workflow", { id: args.workflowId, operations: (args.updates as { operations?: unknown })?.operations ?? args.updates }));
          if (!r.ok) return { status: "error", message: `n8n_update_partial_workflow failed: ${r.rawText}` };
          return { status: "ok", message: "Workflow partially updated.", data: unwrap(r.data) };
        }

        case "delete": {
          if (!args.workflowId) return { status: "error", message: "workflowId is required for action=delete." };
          const r = parseBackend(await call("n8n_delete_workflow", { id: args.workflowId }));
          if (!r.ok) return { status: "error", message: `n8n_delete_workflow failed: ${r.rawText}` };
          return { status: "ok", message: `Workflow ${String(args.workflowId)} deleted.` };
        }

        case "autofix": {
          if (!args.workflowId) return { status: "error", message: "workflowId is required for action=autofix." };
          const r = parseBackend(await call("n8n_autofix_workflow", { id: args.workflowId }));
          if (!r.ok) return { status: "error", message: `n8n_autofix_workflow failed: ${r.rawText}` };
          return { status: "ok", message: "Workflow autofix applied.", data: unwrap(r.data) };
        }

        case "search_nodes": {
          if (!args.query) return { status: "error", message: "query is required for action=search_nodes." };
          const r = parseBackend(await call("search_nodes", { query: args.query }));
          if (!r.ok) return { status: "error", message: `search_nodes failed: ${r.rawText}` };
          if (fmt === "json") return { status: "ok", message: "Nodes found.", data: unwrap(r.data) };
          return { status: "ok", message: "Nodes found.", data: unwrap(r.data) };
        }

        default:
          return {
            status: "error",
            message: `Unknown action: "${action}". Valid actions: list, get, create, update, update_partial, delete, autofix, search_nodes.`,
          };
      }
    },
  };
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  n8n_templates                                                      */
/* ═══════════════════════════════════════════════════════════════════ */

const N8N_TEMPLATES_SCHEMA: Record<string, unknown> = {
  type: "object",
  properties: {
    action: {
      type: "string",
      enum: ["search", "deploy"],
      description: "The operation to perform.",
    },
    query: { type: "string", description: "Search query (required for: search)." },
    templateId: { type: "number", description: "Template ID to deploy (required for: deploy)." },
  },
  required: ["action"],
};

function buildN8nTemplates(call: BackendCallFn): ToolDef {
  return {
    name: "n8n_templates",
    description: "Template management. Actions: search, deploy.",
    inputSchema: N8N_TEMPLATES_SCHEMA,
    handler: async (args): Promise<ToolResult> => {
      const action = String(args.action ?? "");

      switch (action) {
        case "search": {
          if (!args.query) return { status: "error", message: "query is required for action=search." };
          const r = parseBackend(await call("search_templates", { query: args.query }));
          if (!r.ok) return { status: "error", message: `search_templates failed: ${r.rawText}` };
          return { status: "ok", message: "Templates found.", data: unwrap(r.data) };
        }

        case "deploy": {
          if (args.templateId === undefined) return { status: "error", message: "templateId is required for action=deploy." };
          const r = parseBackend(await call("n8n_deploy_template", { templateId: args.templateId }));
          if (!r.ok) return { status: "error", message: `n8n_deploy_template failed: ${r.rawText}` };
          return { status: "ok", message: "Template deployed.", data: unwrap(r.data) };
        }

        default:
          return {
            status: "error",
            message: `Unknown action: "${action}". Valid actions: search, deploy.`,
          };
      }
    },
  };
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  n8n_validate                                                       */
/* ═══════════════════════════════════════════════════════════════════ */

const N8N_VALIDATE_SCHEMA: Record<string, unknown> = {
  type: "object",
  properties: {
    action: {
      type: "string",
      enum: ["by_id", "by_object", "node"],
      description: "Validation mode. by_id: validate by workflowId; by_object: validate workflow JSON; node: validate a node object.",
    },
    workflowId: { type: "string", description: "Workflow ID (required for: by_id)." },
    workflow: { type: "object", description: "Workflow object (required for: by_object)." },
    node: { type: "object", description: "Node object (required for: node)." },
  },
  required: ["action"],
};

function buildN8nValidate(call: BackendCallFn): ToolDef {
  return {
    name: "n8n_validate",
    description: "Workflow validation. Actions: by_id (validate by workflowId), by_object (validate workflow JSON), node (validate a node object).",
    inputSchema: N8N_VALIDATE_SCHEMA,
    handler: async (args): Promise<ToolResult> => {
      const action = String(args.action ?? "");

      switch (action) {
        case "by_id": {
          if (!args.workflowId) return { status: "error", message: "workflowId is required for action=by_id." };
          const r = parseBackend(await call("n8n_validate_workflow", { workflowId: args.workflowId }));
          if (!r.ok) return { status: "error", message: `n8n_validate_workflow failed: ${r.rawText}` };
          return { status: "ok", message: "Validation complete.", data: unwrap(r.data) };
        }

        case "by_object": {
          if (!args.workflow) return { status: "error", message: "workflow object is required for action=by_object." };
          const r = parseBackend(await call("validate_workflow", { workflow: args.workflow }));
          if (!r.ok) return { status: "error", message: `validate_workflow failed: ${r.rawText}` };
          return { status: "ok", message: "Validation complete.", data: unwrap(r.data) };
        }

        case "node": {
          if (!args.node) return { status: "error", message: "node object is required for action=node." };
          const r = parseBackend(await call("validate_node", { node: args.node }));
          if (!r.ok) return { status: "error", message: `validate_node failed: ${r.rawText}` };
          return { status: "ok", message: "Node validation complete.", data: unwrap(r.data) };
        }

        default:
          return {
            status: "error",
            message: `Unknown action: "${action}". Valid actions: by_id, by_object, node.`,
          };
      }
    },
  };
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  n8n_workflow_status (composite)                                    */
/* ═══════════════════════════════════════════════════════════════════ */

const N8N_WORKFLOW_STATUS_SCHEMA: Record<string, unknown> = {
  type: "object",
  properties: {
    workflowId: { type: "string", description: "The workflow ID to inspect." },
  },
  required: ["workflowId"],
};

function buildN8nWorkflowStatus(call: BackendCallFn): ToolDef {
  return {
    name: "n8n_workflow_status",
    description:
      "Single-call workflow health snapshot. Combines workflow details, last 5 executions, and version history.",
    inputSchema: N8N_WORKFLOW_STATUS_SCHEMA,
    handler: async (args): Promise<ToolResult> => {
      const workflowId = String(args.workflowId ?? "");
      if (!workflowId) return { status: "error", message: "workflowId is required." };

      // Fire all three sub-calls concurrently
      const [wfResult, exResult, verResult] = await Promise.allSettled([
        call("n8n_get_workflow", { id: workflowId }),
        call("n8n_executions", { workflowId, limit: 5 }),
        call("n8n_workflow_versions", { workflowId }),
      ]);

      // ── Workflow details ────────────────────────────────────────────
      let wfLine = "unavailable";
      let wfData: Record<string, unknown> | null = null;
      if (wfResult.status === "fulfilled") {
        const p = parseBackend(wfResult.value);
        if (p.ok) {
          wfData = (unwrap(p.data) ?? {}) as Record<string, unknown>;
          const name = safeStr(wfData, "name") || "unknown";
          const active = String(wfData.active ?? "?");
          const triggerType = safeStr(wfData, "triggerType") || "unknown";
          wfLine = `${name} | active:${active} | trigger:${triggerType}`;
        }
      }

      // ── Executions ──────────────────────────────────────────────────
      let exLine = "unavailable";
      if (exResult.status === "fulfilled") {
        const p = parseBackend(exResult.value);
        if (p.ok) {
          const inner = (unwrap(p.data) ?? {}) as Record<string, unknown>;
          const list = (inner.results ?? inner.executions ?? []) as Array<Record<string, unknown>>;
          if (Array.isArray(list)) {
            const total = list.length;
            const successes = list.filter((e) => e.status === "success" || e.finished === true).length;
            // Avg duration in seconds
            const durations = list
              .map((e) => {
                const ms = safeNum(e, "stoppedAt") && safeNum(e, "startedAt")
                  ? (safeNum(e, "stoppedAt") as number) - (safeNum(e, "startedAt") as number)
                  : undefined;
                return ms;
              })
              .filter((d): d is number => d !== undefined && d >= 0);
            const avgDur = durations.length > 0
              ? (durations.reduce((a, b) => a + b, 0) / durations.length / 1000).toFixed(1)
              : "?";
            exLine = `${successes}/${total} success | avg ${avgDur}s`;
          }
        }
      }

      // ── Versions ────────────────────────────────────────────────────
      let verLine = "unavailable";
      if (verResult.status === "fulfilled") {
        const p = parseBackend(verResult.value);
        if (p.ok) {
          const inner = (unwrap(p.data) ?? {}) as Record<string, unknown>;
          const versions = (inner.versions ?? inner) as Array<Record<string, unknown>>;
          if (Array.isArray(versions)) {
            const count = versions.length;
            const latest = versions[0];
            const lastUpdated = latest ? safeStr(latest, "createdAt") || safeStr(latest, "updatedAt") : "";
            verLine = `${count} version(s) | last updated: ${lastUpdated || "unknown"}`;
          } else {
            verLine = JSON.stringify(inner);
          }
        }
      }

      const text = [
        `Workflow: ${wfLine}`,
        `Last 5 executions: ${exLine}`,
        `Versions: ${verLine}`,
      ].join("\n");

      // Partial if any section failed
      const allOk =
        wfResult.status === "fulfilled" &&
        exResult.status === "fulfilled" &&
        verResult.status === "fulfilled";

      return {
        status: allOk ? "ok" : "partial",
        message: text,
        data: wfData ?? undefined,
      };
    },
  };
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  Exported consolidation function                                    */
/* ═══════════════════════════════════════════════════════════════════ */

/** Tool names replaced by consolidated tools */
const HIDDEN_TOOLS = new Set([
  "n8n_list_workflows",
  "n8n_get_workflow",
  "n8n_create_workflow",
  "n8n_update_full_workflow",
  "n8n_update_partial_workflow",
  "n8n_delete_workflow",
  "n8n_autofix_workflow",
  "search_nodes",
  "search_templates",
  "n8n_deploy_template",
  "n8n_validate_workflow",
  "validate_workflow",
  "validate_node",
]);

export const n8nConsolidation: ConsolidateFn = (
  tools: DiscoveredTool[],
  call: BackendCallFn,
): ConsolidationResult => {
  // Only hide tools that actually exist in this backend
  const existingNames = new Set(tools.map((t) => t.name));
  const hidden = [...HIDDEN_TOOLS].filter((name) => existingNames.has(name));

  const consolidated: ToolDef[] = [
    buildN8nWorkflows(call),
    buildN8nTemplates(call),
    buildN8nValidate(call),
    buildN8nWorkflowStatus(call),
  ];

  return { tools: consolidated, hidden };
};
