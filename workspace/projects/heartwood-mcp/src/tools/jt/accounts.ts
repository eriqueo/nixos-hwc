/**
 * JT Accounts & Contacts tools — 6 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import {
  ACCOUNT_FIELDS,
  ACCOUNT_BASIC_FIELDS,
  CONTACT_FIELDS,
} from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildFilter, buildSearchFilter, pickDefined, requireString, PAGINATION_PROPS, getPagination } from "./helpers.js";

export function accountTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_account ──────────────────────────────────────────────
    {
      name: "jt_create_account",
      description:
        "Create a new account (customer or vendor) in JobTread. Org ID injected automatically.",
      inputSchema: {
        type: "object" as const,
        properties: {
          name: { type: "string", description: "Account name" },
          type: {
            type: "string",
            enum: ["customer", "vendor"],
            description: "Account type",
          },
        },
        required: ["name", "type"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.create("createAccount", {
          name: params.name,
          type: params.type,
        }, ACCOUNT_BASIC_FIELDS);
      },
    },

    // ── jt_update_account ──────────────────────────────────────────────
    {
      name: "jt_update_account",
      description:
        "Update an existing account. Handles the ID-based custom field format internally.",
      inputSchema: {
        type: "object" as const,
        properties: {
          id: { type: "string", description: "Account ID" },
          name: { type: "string", description: "New account name (optional)" },
          customFieldValues: {
            type: "array",
            items: {
              type: "object",
              properties: {
                customFieldId: { type: "string" },
                value: { type: "string" },
              },
              required: ["customFieldId", "value"],
            },
            description: "Custom field values to set",
          },
        },
        required: ["id"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "id");
        if ("error" in id) return id.error;
        const data = pickDefined(params, ["name", "customFieldValues"]);
        return pave.update("updateAccount", { id: id.value, ...data }, ACCOUNT_BASIC_FIELDS);
      },
    },

    // ── jt_get_accounts ────────────────────────────────────────────────
    {
      name: "jt_get_accounts",
      description: "Search for accounts by name (partial match). Optionally filter by type.",
      inputSchema: {
        type: "object" as const,
        properties: {
          searchTerm: { type: "string", description: "Partial name match" },
          type: {
            type: "string",
            enum: ["customer", "vendor"],
            description: "Filter by account type (optional)",
          },
          ...PAGINATION_PROPS,
        },
        required: ["searchTerm"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entityPlural: "accounts",
          returnFields: ACCOUNT_FIELDS,
          where: buildSearchFilter(params, "searchTerm", "name", [
            { param: "type", field: "type" },
          ]),
          ...getPagination(params),
        });
      },
    },

    // ── jt_create_contact ──────────────────────────────────────────────
    {
      name: "jt_create_contact",
      description:
        "Create a contact for an account. Uses field names (case-insensitive), not IDs, for custom fields.",
      inputSchema: {
        type: "object" as const,
        properties: {
          accountId: { type: "string", description: "Parent account ID" },
          name: { type: "string", description: "Contact full name" },
          email: { type: "string", description: "Email address (optional)" },
          phone: { type: "string", description: "Phone number (optional)" },
          customFields: {
            type: "object",
            description: "Custom field name→value pairs (case-insensitive)",
            additionalProperties: { type: "string" },
          },
        },
        required: ["accountId", "name"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          accountId: params.accountId,
          name: params.name,
          ...pickDefined(params, ["email", "phone", "customFields"]),
        };
        return pave.create("createContact", data, CONTACT_FIELDS);
      },
    },

    // ── jt_get_contacts ────────────────────────────────────────────────
    {
      name: "jt_get_contacts",
      description: "Get contacts, optionally filtered by account.",
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
          entityPlural: "contacts",
          returnFields: CONTACT_FIELDS,
          where: buildFilter(params, [
            { param: "accountId", field: "accountId" },
          ]),
          ...getPagination(params),
        });
      },
    },

    // ── jt_get_contact_details ─────────────────────────────────────────
    {
      name: "jt_get_contact_details",
      description: "Get full details for a specific contact including custom fields and methods.",
      inputSchema: {
        type: "object" as const,
        properties: {
          contactId: { type: "string", description: "Contact ID" },
        },
        required: ["contactId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "contactId");
        if ("error" in id) return id.error;
        return pave.read("contact", id.value, CONTACT_FIELDS);
      },
    },
  ];
}
