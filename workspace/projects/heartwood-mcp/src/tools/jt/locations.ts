/**
 * JT Location tools — 2 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { LOCATION_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildFilter, pickDefined, PAGINATION_PROPS, getPagination } from "./helpers.js";

export function locationTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_location ─────────────────────────────────────────────
    {
      name: "jt_create_location",
      description:
        "Create a location for an account. Required before creating a job.",
      inputSchema: {
        type: "object" as const,
        properties: {
          accountId: { type: "string", description: "Parent account ID" },
          address: { type: "string", description: "Street address" },
          name: { type: "string", description: "Location name" },
          city: { type: "string", description: "City (optional)" },
          state: { type: "string", description: "State (optional)" },
          zip: { type: "string", description: "ZIP code (optional)" },
          contactId: { type: "string", description: "Associated contact ID (optional)" },
        },
        required: ["accountId", "address", "name"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          accountId: params.accountId,
          address: params.address,
          name: params.name,
          ...pickDefined(params, ["city", "state", "zip", "contactId"]),
        };
        return pave.create("location", data, LOCATION_FIELDS);
      },
    },

    // ── jt_get_locations ───────────────────────────────────────────────
    {
      name: "jt_get_locations",
      description: "Get locations, optionally filtered by account.",
      inputSchema: {
        type: "object" as const,
        properties: {
          accountId: { type: "string", description: "Filter by account ID (optional)" },
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "location",
          fields: LOCATION_FIELDS,
          filter: buildFilter(params, [
            { param: "accountId", field: "accountId" },
          ]),
          ...getPagination(params),
        });
      },
    },
  ];
}
