/**
 * JT Daily Log tools — 4 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { DAILY_LOG_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

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
        };
        if (params.customFields) data.customFields = params.customFields;
        return pave.create("dailyLog", data, DAILY_LOG_FIELDS);
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
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const conditions: Array<{ field: string; operator: string; value: unknown }> = [];
        if (params.jobId) conditions.push({ field: "jobId", operator: "eq", value: params.jobId });
        if (params.userId) conditions.push({ field: "userId", operator: "eq", value: params.userId });
        if (params.startDate) conditions.push({ field: "date", operator: "gte", value: params.startDate });
        if (params.endDate) conditions.push({ field: "date", operator: "lte", value: params.endDate });
        return pave.query({
          entity: "dailyLog",
          fields: DAILY_LOG_FIELDS,
          filter: conditions.length > 0 ? { operator: "and", conditions } : undefined,
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
        return pave.read("dailyLog", params.logId as string, DAILY_LOG_FIELDS);
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
        };
        if (params.groupBy) data.groupBy = params.groupBy;
        if (params.jobId) data.jobId = params.jobId;
        if (params.userId) data.userId = params.userId;
        return pave.execute({
          action: "query",
          entity: "dailyLogSummary",
          data,
        });
      },
    },
  ];
}
