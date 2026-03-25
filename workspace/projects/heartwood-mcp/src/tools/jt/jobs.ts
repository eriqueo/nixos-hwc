/**
 * JT Job tools — 5 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { JOB_FIELDS, JOB_DETAIL_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

export function jobTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_job ──────────────────────────────────────────────────
    {
      name: "jt_create_job",
      description:
        "Create a new job. Uses field names (not IDs) for custom fields.",
      inputSchema: {
        type: "object" as const,
        properties: {
          locationId: { type: "string", description: "Location ID (required)" },
          name: { type: "string", description: "Job name" },
          description: { type: "string", description: "Job description (optional)" },
          number: { type: "string", description: "Job number (optional, auto-generated if omitted)" },
          customFields: {
            type: "object",
            description: "Custom field name→value pairs (case-insensitive)",
            additionalProperties: { type: "string" },
          },
        },
        required: ["locationId", "name"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          locationId: params.locationId,
          name: params.name,
        };
        if (params.description) data.description = params.description;
        if (params.number) data.number = params.number;
        if (params.customFields) data.customFields = params.customFields;
        return pave.create("job", data, JOB_FIELDS);
      },
    },

    // ── jt_search_jobs ─────────────────────────────────────────────────
    {
      name: "jt_search_jobs",
      description: "Search for jobs by name or number.",
      inputSchema: {
        type: "object" as const,
        properties: {
          searchTerm: { type: "string", description: "Search term" },
          searchBy: {
            type: "string",
            enum: ["name", "number"],
            description: "Search by field (default: name)",
          },
          status: {
            type: "string",
            enum: ["open", "closed", "all"],
            description: "Filter by status (default: all)",
          },
        },
        required: ["searchTerm"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const searchField = (params.searchBy as string) || "name";
        const conditions: Array<{ field: string; operator: string; value: unknown }> = [
          { field: searchField, operator: "like", value: `%${params.searchTerm}%` },
        ];
        if (params.status && params.status !== "all") {
          conditions.push({ field: "status", operator: "eq", value: params.status });
        }
        return pave.query({
          entity: "job",
          fields: JOB_FIELDS,
          filter: { operator: "and", conditions },
        });
      },
    },

    // ── jt_get_job_details ─────────────────────────────────────────────
    {
      name: "jt_get_job_details",
      description:
        "Get full details for a job: location, account, custom fields, files, and documents.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
        },
        required: ["jobId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.read("job", params.jobId as string, JOB_DETAIL_FIELDS);
      },
    },

    // ── jt_get_active_jobs ─────────────────────────────────────────────
    {
      name: "jt_get_active_jobs",
      description: "Get all active jobs (jobs with approved customer orders).",
      inputSchema: {
        type: "object" as const,
        properties: {},
        required: [],
      },
      handler: async (): Promise<ToolResult> => {
        return pave.query({
          entity: "job",
          fields: JOB_FIELDS,
          filter: { conditions: [{ field: "status", operator: "eq", value: "open" }] },
          sort: [{ field: "updatedAt", direction: "desc" }],
        });
      },
    },

    // ── jt_set_job_parameters ──────────────────────────────────────────
    {
      name: "jt_set_job_parameters",
      description: "Set parameters on a job for formula-driven budgets.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
          parameters: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                value: { type: "string" },
              },
              required: ["name", "value"],
            },
            description: "Parameters to set",
          },
        },
        required: ["jobId", "parameters"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.update("job", params.jobId as string, {
          parameters: params.parameters,
        });
      },
    },
  ];
}
