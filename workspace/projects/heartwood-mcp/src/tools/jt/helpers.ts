/**
 * Shared helpers for JT tool handlers.
 */

import type { PaveWhere, PaveWhereCondition, ToolResult } from "../../pave/types.js";

/**
 * Build a PAVE where clause from optional params.
 * Only includes conditions for params that are not undefined.
 * Returns PaveWhere with `and` array, or undefined if no conditions.
 */
export function buildFilter(
  params: Record<string, unknown>,
  mappings: Array<{ param: string; field: string; operator?: string }>
): PaveWhere | undefined {
  const conditions: PaveWhereCondition[] = [];
  for (const { param, field, operator } of mappings) {
    if (params[param] !== undefined) {
      conditions.push([field, operator ?? "=", params[param]]);
    }
  }
  return conditions.length > 0 ? { and: [conditions] } : undefined;
}

/**
 * Build a search filter (wraps value with % for LIKE).
 */
export function buildSearchFilter(
  params: Record<string, unknown>,
  searchParam: string,
  searchField: string,
  extraMappings?: Array<{ param: string; field: string; operator?: string }>
): PaveWhere | undefined {
  const conditions: PaveWhereCondition[] = [];
  if (params[searchParam] !== undefined) {
    conditions.push([searchField, "like", `%${params[searchParam]}%`]);
  }
  if (extraMappings) {
    for (const { param, field, operator } of extraMappings) {
      if (params[param] !== undefined) {
        conditions.push([field, operator ?? "=", params[param]]);
      }
    }
  }
  return conditions.length > 0 ? { and: [conditions] } : undefined;
}

/**
 * Pick defined optional fields from params into a data object.
 * Uses !== undefined (not truthiness) to preserve empty strings and zero values.
 */
export function pickDefined(
  params: Record<string, unknown>,
  fields: string[]
): Record<string, unknown> {
  const data: Record<string, unknown> = {};
  for (const field of fields) {
    if (params[field] !== undefined) {
      data[field] = params[field];
    }
  }
  return data;
}

/**
 * Require a string parameter, returning a typed result or error.
 */
export function requireString(
  params: Record<string, unknown>,
  name: string
): { value: string } | { error: ToolResult } {
  const val = params[name];
  if (typeof val !== "string" || val.length === 0) {
    return {
      error: {
        success: false,
        error: `Parameter "${name}" must be a non-empty string, got ${typeof val}`,
        code: "VALIDATION_ERROR",
      },
    };
  }
  return { value: val };
}

/**
 * Allowed entity types for custom field searches.
 */
export const ALLOWED_ENTITY_TYPES = [
  "account", "contact", "job", "document", "task",
  "timeEntry", "dailyLog", "costItem", "file", "comment",
] as const;

export type AllowedEntityType = typeof ALLOWED_ENTITY_TYPES[number];

/**
 * Standard pagination properties to spread into any query tool's inputSchema.
 * PAVE uses size/after for cursor-based pagination.
 */
export const PAGINATION_PROPS = {
  limit: {
    type: "number",
    description: "Maximum number of results to return (optional, default varies by entity)",
  },
} as const;

/**
 * Extract pagination params from tool params.
 * Maps 'limit' to PAVE's 'size' parameter.
 */
export function getPagination(params: Record<string, unknown>): {
  size?: number;
} {
  const result: { size?: number } = {};
  if (typeof params.limit === "number") result.size = params.limit;
  return result;
}

/**
 * Timezone note for date fields.
 * All date-only fields (YYYY-MM-DD) are interpreted in the org's timezone (America/Denver).
 * All datetime fields must include timezone (ISO 8601 with offset, e.g., 2026-03-25T08:00:00-06:00).
 */
export const TZ_NOTE = "Dates are YYYY-MM-DD in org timezone (America/Denver). " +
  "Datetimes must be ISO 8601 with timezone offset (e.g., 2026-03-25T08:00:00-06:00).";
