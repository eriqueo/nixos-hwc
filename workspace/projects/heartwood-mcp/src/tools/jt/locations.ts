/**
 * JT Location tools — 2 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { LOCATION_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

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
        };
        if (params.city) data.city = params.city;
        if (params.state) data.state = params.state;
        if (params.zip) data.zip = params.zip;
        if (params.contactId) data.contactId = params.contactId;
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
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const filter = params.accountId
          ? { conditions: [{ field: "accountId", operator: "eq" as const, value: params.accountId }] }
          : undefined;
        return pave.query({
          entity: "location",
          fields: LOCATION_FIELDS,
          filter,
        });
      },
    },
  ];
}
