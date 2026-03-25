/**
 * JT Time Entry tools — 4 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { TIME_ENTRY_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

export function timeEntryTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_time_entry ───────────────────────────────────────────
    {
      name: "jt_create_time_entry",
      description:
        "Create a time entry for a job. Dates must be ISO 8601 with timezone.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
          userId: { type: "string", description: "User ID" },
          startedAt: { type: "string", description: "Start time (ISO 8601 with timezone)" },
          endedAt: { type: "string", description: "End time (ISO 8601 with timezone)" },
          notes: { type: "string", description: "Notes (optional)" },
          costItemId: { type: "string", description: "Cost item ID (optional)" },
          type: { type: "string", description: "Time entry type (optional)" },
          isApproved: { type: "boolean", description: "Mark as approved (optional)" },
        },
        required: ["jobId", "userId", "startedAt", "endedAt"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          jobId: params.jobId,
          userId: params.userId,
          startedAt: params.startedAt,
          endedAt: params.endedAt,
        };
        for (const field of ["notes", "costItemId", "type", "isApproved"]) {
          if (params[field] !== undefined) data[field] = params[field];
        }
        return pave.create("timeEntry", data, TIME_ENTRY_FIELDS);
      },
    },

    // ── jt_get_time_entries ────────────────────────────────────────────
    {
      name: "jt_get_time_entries",
      description: "Get time entries with optional filters.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Filter by job ID (optional)" },
          userId: { type: "string", description: "Filter by user ID (optional)" },
          startDate: { type: "string", description: "Filter entries after this date (optional)" },
          endDate: { type: "string", description: "Filter entries before this date (optional)" },
          isApproved: { type: "boolean", description: "Filter by approval status (optional)" },
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const conditions: Array<{ field: string; operator: string; value: unknown }> = [];
        if (params.jobId) conditions.push({ field: "jobId", operator: "eq", value: params.jobId });
        if (params.userId) conditions.push({ field: "userId", operator: "eq", value: params.userId });
        if (params.startDate) conditions.push({ field: "startedAt", operator: "gte", value: params.startDate });
        if (params.endDate) conditions.push({ field: "endedAt", operator: "lte", value: params.endDate });
        if (params.isApproved !== undefined) conditions.push({ field: "isApproved", operator: "eq", value: params.isApproved });
        return pave.query({
          entity: "timeEntry",
          fields: TIME_ENTRY_FIELDS,
          filter: conditions.length > 0 ? { operator: "and", conditions } : undefined,
        });
      },
    },

    // ── jt_get_time_entry_details ──────────────────────────────────────
    {
      name: "jt_get_time_entry_details",
      description: "Get full details for a specific time entry.",
      inputSchema: {
        type: "object" as const,
        properties: {
          timeEntryId: { type: "string", description: "Time entry ID" },
        },
        required: ["timeEntryId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.read("timeEntry", params.timeEntryId as string, TIME_ENTRY_FIELDS);
      },
    },

    // ── jt_get_time_summary ────────────────────────────────────────────
    {
      name: "jt_get_time_summary",
      description: "Get aggregated time summary for a date range.",
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
          entity: "timeSummary",
          data,
        });
      },
    },
  ];
}
