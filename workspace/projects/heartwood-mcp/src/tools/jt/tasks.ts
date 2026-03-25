/**
 * JT Task tools — 7 tools
 */

import type { PaveClient, ToolResult } from "../../pave/index.js";
import { TASK_FIELDS, TEMPLATE_FIELDS } from "../../pave/index.js";
import type { ToolDef } from "../registry.js";
import { buildFilter, pickDefined, requireString, PAGINATION_PROPS, getPagination } from "./helpers.js";

export function taskTools(pave: PaveClient): ToolDef[] {
  return [
    // ── jt_create_task ─────────────────────────────────────────────────
    {
      name: "jt_create_task",
      description: "Create a task on a target (job, document, etc.).",
      inputSchema: {
        type: "object" as const,
        properties: {
          name: { type: "string", description: "Task name" },
          targetType: { type: "string", description: "Target entity type (e.g., 'job')" },
          targetId: { type: "string", description: "Target entity ID (optional)" },
          description: { type: "string", description: "Task description (optional)" },
          assignees: {
            type: "array", items: { type: "string" },
            description: "User IDs to assign (optional)",
          },
          startDate: { type: "string", description: "Start date YYYY-MM-DD (optional)" },
          endDate: { type: "string", description: "End date YYYY-MM-DD (optional)" },
          isToDo: { type: "boolean", description: "Is this a to-do item (optional)" },
          isGroup: { type: "boolean", description: "Is this a task group (optional)" },
          progress: { type: "number", description: "Progress 0-100 (optional)" },
        },
        required: ["name", "targetType"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const data: Record<string, unknown> = {
          name: params.name,
          targetType: params.targetType,
          ...pickDefined(params, [
            "targetId", "description", "assignees", "startDate",
            "endDate", "isToDo", "isGroup", "progress",
          ]),
        };
        return pave.create("task", data, TASK_FIELDS);
      },
    },

    // ── jt_update_task_progress ────────────────────────────────────────
    {
      name: "jt_update_task_progress",
      description: "Update a task's progress, name, description, or dates.",
      inputSchema: {
        type: "object" as const,
        properties: {
          taskId: { type: "string", description: "Task ID" },
          progress: { type: "number", description: "Progress 0-100 (optional)" },
          name: { type: "string", description: "New name (optional)" },
          description: { type: "string", description: "New description (optional)" },
          startDate: { type: "string", description: "Start date YYYY-MM-DD (optional)" },
          endDate: { type: "string", description: "End date YYYY-MM-DD (optional)" },
        },
        required: ["taskId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "taskId");
        if ("error" in id) return id.error;
        const data = pickDefined(params, ["progress", "name", "description", "startDate", "endDate"]);
        return pave.update("task", id.value, data, TASK_FIELDS);
      },
    },

    // ── jt_get_tasks ───────────────────────────────────────────────────
    {
      name: "jt_get_tasks",
      description: "Get tasks, optionally filtered by job, status, or assignee.",
      inputSchema: {
        type: "object" as const,
        properties: {
          jobId: { type: "string", description: "Filter by job ID (optional)" },
          status: { type: "string", description: "Filter by status (optional)" },
          assigneeUserId: { type: "string", description: "Filter by assignee user ID (optional)" },
          ...PAGINATION_PROPS,
        },
        required: [],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        return pave.query({
          entity: "task",
          fields: TASK_FIELDS,
          filter: buildFilter(params, [
            { param: "jobId", field: "jobId" },
            { param: "status", field: "status" },
            { param: "assigneeUserId", field: "assigneeUserId" },
          ]),
          ...getPagination(params),
        });
      },
    },

    // ── jt_get_task_details ────────────────────────────────────────────
    {
      name: "jt_get_task_details",
      description: "Get full task details including assignees and dependencies.",
      inputSchema: {
        type: "object" as const,
        properties: {
          taskId: { type: "string", description: "Task ID" },
        },
        required: ["taskId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "taskId");
        if ("error" in id) return id.error;
        return pave.read("task", id.value, [
          ...TASK_FIELDS,
          { field: "dependencies", fields: [{ field: "id" }, { field: "name" }] },
        ]);
      },
    },

    // ── jt_get_schedule_templates ──────────────────────────────────────
    {
      name: "jt_get_schedule_templates",
      description: "Get all schedule templates.",
      inputSchema: {
        type: "object" as const,
        properties: {},
        required: [],
      },
      handler: async (): Promise<ToolResult> => {
        return pave.query({
          entity: "scheduleTemplate",
          fields: TEMPLATE_FIELDS,
        });
      },
    },

    // ── jt_get_todo_templates ──────────────────────────────────────────
    {
      name: "jt_get_todo_templates",
      description: "Get all to-do templates.",
      inputSchema: {
        type: "object" as const,
        properties: {},
        required: [],
      },
      handler: async (): Promise<ToolResult> => {
        return pave.query({
          entity: "todoTemplate",
          fields: TEMPLATE_FIELDS,
        });
      },
    },

    // ── jt_get_task_template_details ───────────────────────────────────
    {
      name: "jt_get_task_template_details",
      description: "Get the tasks inside a specific task template.",
      inputSchema: {
        type: "object" as const,
        properties: {
          taskTemplateId: { type: "string", description: "Task template ID" },
        },
        required: ["taskTemplateId"],
      },
      handler: async (params: Record<string, unknown>): Promise<ToolResult> => {
        const id = requireString(params, "taskTemplateId");
        if ("error" in id) return id.error;
        return pave.read("taskTemplate", id.value, [
          ...TEMPLATE_FIELDS,
          { field: "tasks", fields: TASK_FIELDS },
        ]);
      },
    },
  ];
}
