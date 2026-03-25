/**
 * JT Job Folders tool — 1 tool (part of Files category)
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { PAGINATION_PROPS, getPagination } from "./helpers.js";

export function jobFolderTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_get_job_folders ─────────────────────────────────────────────
    {
      name: "jt_get_job_folders",
      description: "Get available folder names for a job.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Job ID" },
          ...PAGINATION_PROPS,
        },
        required: ["jobId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entityPlural: "jobFolders",
          returnFields: { name: {} },
          where: { and: [[["jobId", "=", params.jobId]]] },
          ...getPagination(params),
        });
      },
    },
  ];
}
