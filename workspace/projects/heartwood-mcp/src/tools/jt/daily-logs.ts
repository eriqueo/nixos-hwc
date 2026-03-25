/**
 * JT Daily Log tools — 4 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { DAILY_LOG_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildFilter, pickDefined, requireString, PAGINATION_PROPS, getPagination } from "./helpers.js";

export function dailyLogTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_daily_log ────────────────────────────────────────────
    {
      name: "jt_create_daily_log",
      description: "Create a daily log entry. Custom field names are case-insensitive.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
          date: { type: "string", description: "Log date (YYYY-MM-DD)" },
          notes: { type: "string", description: "Log notes" },
          customFields: {
            type: "object",
            description: "Custom field name→value pairs (case-insensitive)",
            additionalProperties: { type: "string" },
          },
        },
        required: ["jobId", "date", "notes"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          jobId: params.jobId,
          date: params.date,
          notes: params.notes,
          ...pickDefined(params, ["customFields"]),
        };
        return pave.create("createDailyLog", data, DAILY_LOG_FIELDS);
      },
    },

    // ── jt_get_daily_logs ──────────────────────────────────────────────
    {
      name: "jt_get_daily_logs",
      description: "Get daily logs with optional filters.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Filter by job ID (optional)" },
          userId: { type: "string", description: "Filter by user ID (optional)" },
          startDate: { type: "string", description: "Filter after this date (optional)" },
          endDate: { type: "string", description: "Filter before this date (optional)" },
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entityPlural: "dailyLogs",
          returnFields: DAILY_LOG_FIELDS,
          where: buildFilter(params, [
            { param: "jobId", field: "jobId" },
            { param: "userId", field: "userId" },
            { param: "startDate", field: "date", operator: ">=" },
            { param: "endDate", field: "date", operator: "<=" },
          ]),
          ...getPagination(params),
        });
      },
    },

    // ── jt_get_daily_log_details ───────────────────────────────────────
    {
      name: "jt_get_daily_log_details",
      description: "Get full details for a specific daily log.",
      inputSchema: {
        type: "object" as const,
        properties: {
          logId: { type: "string", description: "Daily log ID" },
        },
        required: ["logId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "logId");
        if ("error" in id) return id.error;
        return pave.read("dailyLog", id.value, DAILY_LOG_FIELDS);
      },
    },

    // ── jt_get_daily_logs_summary ──────────────────────────────────────
    {
      name: "jt_get_daily_logs_summary",
      description: "Get aggregated daily logs summary for a date range.",
      inputSchema: {
        type: "object" as const,
        properties: {
          startDate: { type: "string", description: "Start date (YYYY-MM-DD)" },
          endDate: { type: "string", description: "End date (YYYY-MM-DD)" },
          groupBy: { type: "string", description: "Group by field (optional)" },
          jobId: { type: "string", description: "Filter by job ID (optional)" },
          userId: { type: "string", description: "Filter by user ID (optional)" },
        },
        required: ["startDate", "endDate"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          startDate: params.startDate,
          endDate: params.endDate,
          ...pickDefined(params, ["groupBy", "jobId", "userId"]),
        };
        // dailyLogSummary is a special query operation
        return pave.raw({
          dailyLogSummary: {
            $: data,
          },
        });
      },
    },
  ];
}
