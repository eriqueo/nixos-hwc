/**
 * JT Custom Fields & Search tools — 2 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { CUSTOM_FIELD_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

export function customFieldTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_get_custom_fields ───────────────────────────────────────────
    {
      name: "jt_get_custom_fields",
      description: "Get custom field definitions for an entity type. Use to discover field IDs dynamically.",
      inputSchema: {
        type: "object" as const,
        properties: {
          targetType: {
            type: "string",
            description: "Entity type (e.g., 'account', 'contact', 'job', 'dailyLog')",
          },
        },
        required: ["targetType"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "customField",
          fields: CUSTOM_FIELD_FIELDS,
          filter: { conditions: [{ field: "targetType", operator: "eq", value: params.targetType }] },
        });
      },
    },

    // ── jt_search_by_custom_field ──────────────────────────────────────
    {
      name: "jt_search_by_custom_field",
      description: "Search entities by a custom field value.",
      inputSchema: {
        type: "object" as const,
        properties: {
          entityType: { type: "string", description: "Entity type to search (e.g., 'job', 'account')" },
          customFieldName: { type: "string", description: "Custom field name (case-insensitive)" },
          customFieldValue: { type: "string", description: "Value to search for" },
          operator: {
            type: "string",
            enum: ["eq", "like", "neq"],
            description: "Comparison operator (default: eq)",
          },
        },
        required: ["entityType", "customFieldName", "customFieldValue"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const op = (params.operator as string) || "eq";
        const value = op === "like" ? `%${params.customFieldValue}%` : params.customFieldValue;
        return pave.query({
          entity: params.entityType as string,
          filter: {
            conditions: [{
              field: `customField.${params.customFieldName}`,
              operator: op,
              value,
            }],
          },
        });
      },
    },
  ];
}
