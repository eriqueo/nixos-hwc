/**
 * JT Dashboard tools — 3 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { DASHBOARD_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

export function dashboardTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_dashboard ────────────────────────────────────────────
    {
      name: "jt_create_dashboard",
      description: "Create a dashboard with tiles configuration.",
      inputSchema: {
        type: "object" as const,
        properties: {
          name: { type: "string", description: "Dashboard name" },
          tiles: { type: "string", description: "Tiles configuration as JSON string" },
        },
        required: ["name", "tiles"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.create("dashboard", {
          name: params.name,
          tiles: params.tiles,
        }, DASHBOARD_FIELDS);
      },
    },

    // ── jt_update_dashboard ────────────────────────────────────────────
    {
      name: "jt_update_dashboard",
      description: "Update a dashboard's tiles configuration.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: { type: "string", description: "Dashboard ID" },
          tiles: { type: "string", description: "New tiles configuration as JSON string" },
        },
        required: ["id", "tiles"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.update("dashboard", params.id as string, {
          tiles: params.tiles,
        }, DASHBOARD_FIELDS);
      },
    },

    // ── jt_get_dashboards ──────────────────────────────────────────────
    {
      name: "jt_get_dashboards",
      description: "Get dashboards, optionally filtered by name.",
      inputSchema: {
        type: "object" as const,
        properties: {
          name: { type: "string", description: "Filter by name (optional)" },
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const filter = params.name
          ? { conditions: [{ field: "name", operator: "like" as const, value: `%${params.name}%` }] }
          : undefined;
        return pave.query({
          entity: "dashboard",
          fields: DASHBOARD_FIELDS,
          filter,
        });
      },
    },
  ];
}
