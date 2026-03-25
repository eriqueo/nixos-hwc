/**
 * JT File tools — 7 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { FILE_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildFilter, pickDefined, requireString, PAGINATION_PROPS, getPagination } from "./helpers.js";

export function fileTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_upload_file ─────────────────────────────────────────────────
    {
      name: "jt_upload_file",
      description:
        "Upload a file to a target entity. Requires a public HTTPS URL.",
      inputSchema: {
        type: "object" as const,
        properties: {
          targetId: { type: "string", description: "Target entity ID" },
          targetType: { type: "string", description: "Target entity type (e.g., 'job')" },
          url: { type: "string", description: "Public HTTPS URL of the file" },
          name: { type: "string", description: "File name (optional)" },
          folder: { type: "string", description: "Folder name (optional)" },
          fileTagIds: {
            type: "array", items: { type: "string" },
            description: "File tag IDs (optional)",
          },
        },
        required: ["targetId", "targetType", "url"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          targetId: params.targetId,
          targetType: params.targetType,
          url: params.url,
          ...pickDefined(params, ["name", "folder", "fileTagIds"]),
        };
        return pave.create("file", data, FILE_FIELDS);
      },
    },

    // ── jt_update_file ─────────────────────────────────────────────────
    {
      name: "jt_update_file",
      description: "Update a file's metadata (name, folder, tags, description).",
      inputSchema: {
        type: "object" as const,
        properties: {
          fileId: { type: "string", description: "File ID" },
          name: { type: "string", description: "New name (optional)" },
          folder: { type: "string", description: "New folder (optional)" },
          fileTagIds: {
            type: "array", items: { type: "string" },
            description: "File tag IDs (optional)",
          },
          description: { type: "string", description: "Description (optional)" },
        },
        required: ["fileId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "fileId");
        if ("error" in id) return id.error;
        const data = pickDefined(params, ["name", "folder", "fileTagIds", "description"]);
        return pave.update("file", id.value, data, FILE_FIELDS);
      },
    },

    // ── jt_copy_file ───────────────────────────────────────────────────
    {
      name: "jt_copy_file",
      description: "Copy a file to a different target entity.",
      inputSchema: {
        type: "object" as const,
        properties: {
          sourceFileId: { type: "string", description: "Source file ID" },
          targetId: { type: "string", description: "Target entity ID" },
          targetType: { type: "string", description: "Target entity type" },
          name: { type: "string", description: "New file name (optional)" },
          folder: { type: "string", description: "Target folder (optional)" },
          fileTagIds: {
            type: "array", items: { type: "string" },
            description: "File tag IDs (optional)",
          },
        },
        required: ["sourceFileId", "targetId", "targetType"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          sourceFileId: params.sourceFileId,
          targetId: params.targetId,
          targetType: params.targetType,
          ...pickDefined(params, ["name", "folder", "fileTagIds"]),
        };
        return pave.create("fileCopy", data, FILE_FIELDS);
      },
    },

    // ── jt_read_file ───────────────────────────────────────────────────
    {
      name: "jt_read_file",
      description: "Read a file's content inline.",
      inputSchema: {
        type: "object" as const,
        properties: {
          fileId: { type: "string", description: "File ID" },
        },
        required: ["fileId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "fileId");
        if ("error" in id) return id.error;
        return pave.read("file", id.value, [
          ...FILE_FIELDS,
          { field: "content" },
        ]);
      },
    },

    // ── jt_attach_file_to_budget_item ──────────────────────────────────
    {
      name: "jt_attach_file_to_budget_item",
      description:
        "Attach a file (already uploaded to a job) to a budget item. Upload to the job first, then attach.",
      inputSchema: {
        type: "object" as const,
        properties: {
          fileId: { type: "string", description: "File ID (must already be on the job)" },
          jobId: { type: "string", description: "Job ID" },
          targetId: { type: "string", description: "Cost item or cost group ID" },
          targetType: {
            type: "string",
            enum: ["costItem", "costGroup"],
            description: "Target type",
          },
        },
        required: ["fileId", "jobId", "targetId", "targetType"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.create("fileAttachment", {
          fileId: params.fileId,
          jobId: params.jobId,
          targetId: params.targetId,
          targetType: params.targetType,
        });
      },
    },

    // ── jt_get_files ───────────────────────────────────────────────────
    {
      name: "jt_get_files",
      description: "Get files, optionally filtered by job, document, or folder.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Filter by job ID (optional)" },
          documentId: { type: "string", description: "Filter by document ID (optional)" },
          folder: { type: "string", description: "Filter by folder name (optional)" },
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "file",
          fields: FILE_FIELDS,
          filter: buildFilter(params, [
            { param: "jobId", field: "jobId" },
            { param: "documentId", field: "documentId" },
            { param: "folder", field: "folder" },
          ]),
          ...getPagination(params),
        });
      },
    },

    // ── jt_get_file_tags ───────────────────────────────────────────────
    {
      name: "jt_get_file_tags",
      description: "Get all organization-level file tags.",
      inputSchema: {
        type: "object" as const,
        properties: {
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "fileTag",
          fields: [{ field: "id" }, { field: "name" }],
          ...getPagination(params),
        });
      },
    },
  ];
}
