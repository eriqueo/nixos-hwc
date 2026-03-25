/**
 * JT Document tools — 5 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { DOCUMENT_FIELDS, DOCUMENT_LINE_ITEM_FIELDS, TEMPLATE_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

export function documentTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_document ─────────────────────────────────────────────
    {
      name: "jt_create_document",
      description:
        "Create a document (customerOrder, customerInvoice, vendorOrder, vendorBill, bidRequest).",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
          type: {
            type: "string",
            enum: ["customerOrder", "customerInvoice", "vendorOrder", "vendorBill", "bidRequest"],
            description: "Document type",
          },
          accountId: { type: "string", description: "Account ID (optional)" },
          documentTemplateId: { type: "string", description: "Template ID (optional)" },
          costCodeIds: {
            type: "array", items: { type: "string" },
            description: "Cost code IDs to include (optional)",
          },
          costGroupNames: {
            type: "array", items: { type: "string" },
            description: "Cost group names to include (optional)",
          },
          costItemIds: {
            type: "array", items: { type: "string" },
            description: "Cost item IDs to include (optional)",
          },
          costItemOverrides: {
            type: "array",
            items: {
              type: "object",
              properties: {
                costItemId: { type: "string" },
                quantity: { type: "number" },
                unitPrice: { type: "number" },
              },
            },
            description: "Cost item overrides (optional)",
          },
          date: { type: "string", description: "Document date (optional)" },
          name: { type: "string", description: "Document name (optional)" },
          subject: { type: "string", description: "Subject line (optional)" },
          description: { type: "string", description: "Description (optional)" },
          footer: { type: "string", description: "Footer text (optional)" },
          externalId: { type: "string", description: "External ID (optional)" },
          taxRate: { type: "number", description: "Tax rate as decimal (optional)" },
        },
        required: ["jobId", "type"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          jobId: params.jobId,
          type: params.type,
        };
        const optionalFields = [
          "accountId", "documentTemplateId", "costCodeIds", "costGroupNames",
          "costItemIds", "costItemOverrides", "date", "name", "subject",
          "description", "footer", "externalId", "taxRate",
        ];
        for (const field of optionalFields) {
          if (params[field] !== undefined) data[field] = params[field];
        }
        return pave.create("document", data, DOCUMENT_FIELDS);
      },
    },

    // ── jt_update_document ─────────────────────────────────────────────
    {
      name: "jt_update_document",
      description: "Update a document's status, description, cost items, or push to QBO.",
      inputSchema: {
        type: "object" as const,
        properties: {
          documentId: { type: "string", description: "Document ID" },
          status: { type: "string", description: "New status (optional)" },
          description: { type: "string", description: "New description (optional)" },
          costItemUpdates: {
            type: "array",
            items: {
              type: "object",
              properties: {
                costItemId: { type: "string" },
                quantity: { type: "number" },
                unitPrice: { type: "number" },
              },
            },
            description: "Cost item updates (optional)",
          },
          pushToQbo: { type: "boolean", description: "Push to QuickBooks Online (optional)" },
        },
        required: ["documentId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {};
        if (params.status) data.status = params.status;
        if (params.description) data.description = params.description;
        if (params.costItemUpdates) data.costItemUpdates = params.costItemUpdates;
        if (params.pushToQbo !== undefined) data.pushToQbo = params.pushToQbo;
        return pave.update("document", params.documentId as string, data, DOCUMENT_FIELDS);
      },
    },

    // ── jt_get_documents ───────────────────────────────────────────────
    {
      name: "jt_get_documents",
      description: "Get documents, optionally filtered by job and/or type.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Filter by job ID (optional)" },
          type: {
            type: "string",
            enum: ["customerOrder", "customerInvoice", "vendorOrder", "vendorBill", "bidRequest"],
            description: "Filter by document type (optional)",
          },
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const conditions: Array<{ field: string; operator: string; value: unknown }> = [];
        if (params.jobId) conditions.push({ field: "jobId", operator: "eq", value: params.jobId });
        if (params.type) conditions.push({ field: "type", operator: "eq", value: params.type });
        return pave.query({
          entity: "document",
          fields: DOCUMENT_FIELDS,
          filter: conditions.length > 0 ? { operator: "and", conditions } : undefined,
        });
      },
    },

    // ── jt_get_document_line_items ─────────────────────────────────────
    {
      name: "jt_get_document_line_items",
      description: "Get the line items (groups + items) for a specific document.",
      inputSchema: {
        type: "object" as const,
        properties: {
          documentId: { type: "string", description: "Document ID" },
        },
        required: ["documentId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "documentLineItem",
          fields: DOCUMENT_LINE_ITEM_FIELDS,
          filter: { conditions: [{ field: "documentId", operator: "eq", value: params.documentId }] },
        });
      },
    },

    // ── jt_get_document_templates ──────────────────────────────────────
    {
      name: "jt_get_document_templates",
      description: "Get document templates by type. Use to find template ID before creating a document.",
      inputSchema: {
        type: "object" as const,
        properties: {
          type: {
            type: "string",
            enum: ["customerOrder", "customerInvoice", "vendorOrder", "vendorBill", "bidRequest"],
            description: "Document type to get templates for",
          },
        },
        required: ["type"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "documentTemplate",
          fields: TEMPLATE_FIELDS,
          filter: { conditions: [{ field: "type", operator: "eq", value: params.type }] },
        });
      },
    },
  ];
}
