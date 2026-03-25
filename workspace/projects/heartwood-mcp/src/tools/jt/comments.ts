/**
 * JT Comment tools — 3 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { COMMENT_FIELDS, COMMENT_DETAIL_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildFilter, pickDefined, requireString, PAGINATION_PROPS, getPagination } from "./helpers.js";

export function commentTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_comment ──────────────────────────────────────────────
    {
      name: "jt_create_comment",
      description: "Create a comment on a target entity.",
      inputSchema: {
        type: "object" as const,
        properties: {
          message: { type: "string", description: "Comment message" },
          name: { type: "string", description: "Author display name" },
          targetId: { type: "string", description: "Target entity ID" },
          targetType: { type: "string", description: "Target entity type" },
          isPinned: { type: "boolean", description: "Pin the comment (optional)" },
          parentCommentId: { type: "string", description: "Parent comment ID for replies (optional)" },
          isVisibleToCustomer: { type: "boolean", description: "Visible to customer (optional)" },
          isVisibleToVendor: { type: "boolean", description: "Visible to vendor (optional)" },
          isVisibleToEmployee: { type: "boolean", description: "Visible to employee (optional)" },
        },
        required: ["message", "name", "targetId", "targetType"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          message: params.message,
          name: params.name,
          targetId: params.targetId,
          targetType: params.targetType,
          ...pickDefined(params, ["isPinned", "parentCommentId", "isVisibleToCustomer", "isVisibleToVendor", "isVisibleToEmployee"]),
        };
        return pave.create("createComment", data, COMMENT_FIELDS);
      },
    },

    // ── jt_get_comments ────────────────────────────────────────────────
    {
      name: "jt_get_comments",
      description: "Get comments, optionally filtered by target.",
      inputSchema: {
        type: "object" as const,
        properties: {
          targetId: { type: "string", description: "Filter by target ID (optional)" },
          targetType: { type: "string", description: "Filter by target type (optional)" },
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entityPlural: "comments",
          returnFields: COMMENT_FIELDS,
          where: buildFilter(params, [
            { param: "targetId", field: "targetId" },
            { param: "targetType", field: "targetType" },
          ]),
          ...getPagination(params),
        });
      },
    },

    // ── jt_get_comment_details ─────────────────────────────────────────
    {
      name: "jt_get_comment_details",
      description: "Get full comment details including thread and attached files.",
      inputSchema: {
        type: "object" as const,
        properties: {
          commentId: { type: "string", description: "Comment ID" },
        },
        required: ["commentId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "commentId");
        if ("error" in id) return id.error;
        return pave.read("comment", id.value, COMMENT_DETAIL_FIELDS);
      },
    },
  ];
}
