/**
 * JT Payment tools — 2 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { PAYMENT_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";

export function paymentTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_payment ──────────────────────────────────────────────
    {
      name: "jt_create_payment",
      description:
        "Create a payment on a document. Auto-detects credit/debit from document type.",
      inputSchema: {
        type: "object" as const,
        properties: {
          amount: { type: "number", description: "Payment amount" },
          date: { type: "string", description: "Payment date (YYYY-MM-DD)" },
          documentId: { type: "string", description: "Document ID" },
          description: { type: "string", description: "Payment description (optional)" },
          paymentType: { type: "string", description: "Payment type (optional)" },
        },
        required: ["amount", "date", "documentId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          amount: params.amount,
          date: params.date,
          documentId: params.documentId,
        };
        if (params.description) data.description = params.description;
        if (params.paymentType) data.paymentType = params.paymentType;
        return pave.create("payment", data, PAYMENT_FIELDS);
      },
    },

    // ── jt_get_payments ────────────────────────────────────────────────
    {
      name: "jt_get_payments",
      description: "Get payments, optionally filtered by job, document, or account.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Filter by job ID (optional)" },
          documentId: { type: "string", description: "Filter by document ID (optional)" },
          accountId: { type: "string", description: "Filter by account ID (optional)" },
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const conditions: Array<{ field: string; operator: string; value: unknown }> = [];
        if (params.jobId) conditions.push({ field: "jobId", operator: "eq", value: params.jobId });
        if (params.documentId) conditions.push({ field: "documentId", operator: "eq", value: params.documentId });
        if (params.accountId) conditions.push({ field: "accountId", operator: "eq", value: params.accountId });
        return pave.query({
          entity: "payment",
          fields: PAYMENT_FIELDS,
          filter: conditions.length > 0 ? { operator: "and", conditions } : undefined,
        });
      },
    },
  ];
}
