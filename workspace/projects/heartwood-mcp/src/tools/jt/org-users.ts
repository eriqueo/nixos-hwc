/**
 * JT Organization & User tools — 3 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { USER_FIELDS, ORG_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildSearchFilter, PAGINATION_PROPS, getPagination } from "./helpers.js";

export function orgUserTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_get_users ───────────────────────────────────────────────────
    {
      name: "jt_get_users",
      description: "Get organization users, optionally filtered by search term.",
      inputSchema: {
        type: "object" as const,
        properties: {
          searchTerm: { type: "string", description: "Search by name (optional)" },
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "user",
          fields: USER_FIELDS,
          filter: buildSearchFilter(params, "searchTerm", "name"),
          ...getPagination(params),
        });
      },
    },

    // ── jt_list_organizations ──────────────────────────────────────────
    {
      name: "jt_list_organizations",
      description: "List all accessible organizations.",
      inputSchema: {
        type: "object" as const,
        properties: {
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({ entity: "organization", fields: ORG_FIELDS, ...getPagination(params) });
      },
    },

    // ── jt_switch_organization ─────────────────────────────────────────
    {
      name: "jt_switch_organization",
      description: "Switch the active organization context.",
      inputSchema: {
        type: "object" as const,
        properties: {
          organizationId: { type: "string", description: "Organization ID to switch to" },
        },
        required: ["organizationId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.execute({
          action: "update",
          entity: "session",
          data: { organizationId: params.organizationId },
        });
      },
    },
  ];
}
