/**
 * JT Budget & Cost Items tools — 9 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import {
  BUDGET_ITEM_FIELDS,
  COST_CODE_FIELDS,
  COST_TYPE_FIELDS,
  UNIT_FIELDS,
  TEMPLATE_FIELDS,
} from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

export function budgetTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_add_budget_line_items ────────────────────────────────────────
    {
      name: "jt_add_budget_line_items",
      description:
        "Add budget line items to a job. CRITICAL for estimate push. " +
        "Enforces pipe-delimited names, numeric types, and > group separator.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
          lineItems: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: {
                  type: "string",
                  description:
                    "Line item name. Use pipe (|) to delimit fields, > for group separator.",
                },
                quantity: { type: "number", description: "Quantity" },
                unitCost: { type: "number", description: "Cost per unit" },
                unitPrice: { type: "number", description: "Price per unit" },
                costCodeId: { type: "string", description: "Cost code ID" },
                costTypeId: { type: "string", description: "Cost type ID" },
                unitId: { type: "string", description: "Unit ID" },
                costGroupName: {
                  type: "string",
                  description: "Cost group name (creates group if needed)",
                },
              },
              required: ["name", "quantity", "unitCost", "unitPrice"],
            },
            description: "Array of line items to add",
          },
        },
        required: ["jobId", "lineItems"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        // Validate line items before sending
        const lineItems = params.lineItems as Array<Record<string, unknown>>;
        for (const item of lineItems) {
          if (typeof item.quantity !== "number" || typeof item.unitCost !== "number" || typeof item.unitPrice !== "number") {
            return {
              success: false,
              error: `Line item "${item.name}" has non-numeric quantity/cost/price. All must be numbers.`,
              code: "VALIDATION_ERROR",
            };
          }
        }
        return pave.create("budgetLineItem", {
          jobId: params.jobId,
          lineItems: params.lineItems,
        }, BUDGET_ITEM_FIELDS);
      },
    },

    // ── jt_get_job_budget ──────────────────────────────────────────────
    {
      name: "jt_get_job_budget",
      description: "Get the full budget for a job — groups + items with costs, prices, margins.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
        },
        required: ["jobId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "budgetLineItem",
          fields: BUDGET_ITEM_FIELDS,
          filter: { conditions: [{ field: "jobId", operator: "eq", value: params.jobId }] },
        });
      },
    },

    // ── jt_get_cost_items ──────────────────────────────────────────────
    {
      name: "jt_get_cost_items",
      description: "Search the organization cost item catalog (not job budget).",
      inputSchema: {
        type: "object" as const,
        properties: {
          searchName: { type: "string", description: "Search by name (optional)" },
          costCodeId: { type: "string", description: "Filter by cost code ID (optional)" },
          costTypeId: { type: "string", description: "Filter by cost type ID (optional)" },
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const conditions: Array<{ field: string; operator: string; value: unknown }> = [];
        if (params.searchName) {
          conditions.push({ field: "name", operator: "like", value: `%${params.searchName}%` });
        }
        if (params.costCodeId) {
          conditions.push({ field: "costCodeId", operator: "eq", value: params.costCodeId });
        }
        if (params.costTypeId) {
          conditions.push({ field: "costTypeId", operator: "eq", value: params.costTypeId });
        }
        return pave.query({
          entity: "costItem",
          fields: BUDGET_ITEM_FIELDS,
          filter: conditions.length > 0 ? { operator: "and", conditions } : undefined,
        });
      },
    },

    // ── jt_create_cost_item ────────────────────────────────────────────
    {
      name: "jt_create_cost_item",
      description: "Add a new cost item to the organization catalog.",
      inputSchema: {
        type: "object" as const,
        properties: {
          name: { type: "string", description: "Cost item name" },
          costCodeId: { type: "string", description: "Cost code ID" },
          costTypeId: { type: "string", description: "Cost type ID" },
          unitId: { type: "string", description: "Unit ID (optional)" },
          unitCost: { type: "number", description: "Default unit cost (optional)" },
          unitPrice: { type: "number", description: "Default unit price (optional)" },
        },
        required: ["name", "costCodeId", "costTypeId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          name: params.name,
          costCodeId: params.costCodeId,
          costTypeId: params.costTypeId,
        };
        if (params.unitId) data.unitId = params.unitId;
        if (params.unitCost !== undefined) data.unitCost = params.unitCost;
        if (params.unitPrice !== undefined) data.unitPrice = params.unitPrice;
        return pave.create("costItem", data, BUDGET_ITEM_FIELDS);
      },
    },

    // ── jt_get_cost_codes ──────────────────────────────────────────────
    {
      name: "jt_get_cost_codes",
      description: "Get all cost codes (26 codes with IDs).",
      inputSchema: {
        type: "object" as const,
        properties: {},
        required: [],
      },
      handler: async (): Promise<ToolResult> => {
        return pave.query({ entity: "costCode", fields: COST_CODE_FIELDS });
      },
    },

    // ── jt_get_cost_types ──────────────────────────────────────────────
    {
      name: "jt_get_cost_types",
      description: "Get all cost types (6 types with IDs).",
      inputSchema: {
        type: "object" as const,
        properties: {},
        required: [],
      },
      handler: async (): Promise<ToolResult> => {
        return pave.query({ entity: "costType", fields: COST_TYPE_FIELDS });
      },
    },

    // ── jt_get_units ───────────────────────────────────────────────────
    {
      name: "jt_get_units",
      description: "Get all units of measure (11 units with IDs).",
      inputSchema: {
        type: "object" as const,
        properties: {},
        required: [],
      },
      handler: async (): Promise<ToolResult> => {
        return pave.query({ entity: "unit", fields: UNIT_FIELDS });
      },
    },

    // ── jt_get_cost_group_templates ────────────────────────────────────
    {
      name: "jt_get_cost_group_templates",
      description: "Get all budget/cost group templates.",
      inputSchema: {
        type: "object" as const,
        properties: {},
        required: [],
      },
      handler: async (): Promise<ToolResult> => {
        return pave.query({ entity: "costGroupTemplate", fields: TEMPLATE_FIELDS });
      },
    },

    // ── jt_get_cost_group_template_details ─────────────────────────────
    {
      name: "jt_get_cost_group_template_details",
      description: "Get the items inside a specific cost group template.",
      inputSchema: {
        type: "object" as const,
        properties: {
          costGroupId: { type: "string", description: "Cost group template ID" },
        },
        required: ["costGroupId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.read("costGroupTemplate", params.costGroupId as string, [
          ...TEMPLATE_FIELDS,
          { field: "items", fields: BUDGET_ITEM_FIELDS },
        ]);
      },
    },
  ];
}
