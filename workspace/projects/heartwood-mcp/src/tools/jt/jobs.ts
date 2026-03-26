/**
 * JT Job tools — 5 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { JOB_FIELDS, JOB_DETAIL_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { pickDefined, requireString, PAGINATION_PROPS, getPagination } from "./helpers.js";

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
          ...pickDefined(params, ["description", "number", "customFields"]),
        };
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
          ...PAGINATION_PROPS,
        },
        required: ["searchTerm"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const searchField = params.searchBy !== undefined ? (params.searchBy as string) : "name";
        const conditions: Array<{ field: string; operator: "eq" | "like"; value: unknown }> = [
          { field: searchField, operator: "like", value: `%${params.searchTerm}%` },
        ];
        if (params.status !== undefined && params.status !== "all") {
          conditions.push({ field: "status", operator: "eq", value: params.status });
        }
        return pave.query({
          entity: "job",
          fields: JOB_FIELDS,
          filter: { operator: "and", conditions },
          ...getPagination(params),
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
        const id = requireString(params, "jobId");
        if ("error" in id) return id.error;
        return pave.read("job", id.value, JOB_DETAIL_FIELDS);
      },
    },

    // ── jt_get_active_jobs ─────────────────────────────────────────────
    {
      name: "jt_get_active_jobs",
      description: "Get all active jobs (jobs with approved customer orders).",
      inputSchema: {
        type: "object" as const,
        properties: {
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "job",
          fields: JOB_FIELDS,
          filter: { conditions: [{ field: "status", operator: "eq", value: "open" }] },
          sort: [{ field: "updatedAt", direction: "desc" }],
          ...getPagination(params),
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
        const id = requireString(params, "jobId");
        if ("error" in id) return id.error;
        return pave.update("job", id.value, {
          parameters: params.parameters,
        });
      },
    },
  ];
}
