/**
 * JT Custom Fields & Search tools — 2 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { CUSTOM_FIELD_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { ALLOWED_ENTITY_TYPES, requireString, PAGINATION_PROPS, getPagination } from "./helpers.js";

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
          ...PAGINATION_PROPS,
        },
        required: ["targetType"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "customField",
          fields: CUSTOM_FIELD_FIELDS,
          filter: { conditions: [{ field: "targetType", operator: "eq", value: params.targetType }] },
          ...getPagination(params),
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
          entityType: {
            type: "string",
            enum: ["account", "contact", "job", "document", "task", "timeEntry", "dailyLog", "costItem", "file", "comment"],
            description: "Entity type to search (e.g., 'job', 'account')",
          },
          customFieldName: { type: "string", description: "Custom field name (case-insensitive)" },
          customFieldValue: { type: "string", description: "Value to search for" },
          operator: {
            type: "string",
            enum: ["eq", "like", "neq"],
            description: "Comparison operator (default: eq)",
          },
          ...PAGINATION_PROPS,
        },
        required: ["entityType", "customFieldName", "customFieldValue"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const entityType = requireString(params, "entityType");
        if ("error" in entityType) return entityType.error;
        if (!(ALLOWED_ENTITY_TYPES as readonly string[]).includes(entityType.value)) {
          return {
            success: false,
            error: `Invalid entityType "${entityType.value}". Must be one of: ${ALLOWED_ENTITY_TYPES.join(", ")}`,
            code: "VALIDATION_ERROR",
          };
        }
        const customFieldName = requireString(params, "customFieldName");
        if ("error" in customFieldName) return customFieldName.error;
        const customFieldValue = requireString(params, "customFieldValue");
        if ("error" in customFieldValue) return customFieldValue.error;
        const op = (typeof params.operator === "string" ? params.operator : "eq") as "eq" | "like";
        const value = op === "like" ? `%${customFieldValue.value}%` : customFieldValue.value;
        return pave.query({
          entity: entityType.value,
          filter: {
            conditions: [{
              field: `customField.${customFieldName.value}`,
              operator: op,
              value,
            }],
          },
          ...getPagination(params),
        });
      },
    },
  ];
}
