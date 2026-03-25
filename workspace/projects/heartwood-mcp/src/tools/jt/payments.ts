/**
 * JT Payment tools — 2 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { PAYMENT_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildFilter, pickDefined, PAGINATION_PROPS, getPagination } from "./helpers.js";

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
          ...pickDefined(params, ["description", "paymentType"]),
        };
        return pave.create("createPayment", data, PAYMENT_FIELDS);
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
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entityPlural: "payments",
          returnFields: PAYMENT_FIELDS,
          where: buildFilter(params, [
            { param: "jobId", field: "jobId" },
            { param: "documentId", field: "documentId" },
            { param: "accountId", field: "accountId" },
          ]),
          ...getPagination(params),
        });
      },
    },
  ];
}
