/**
 * Shared helpers for JT tool handlers.
 */

import type { PaveCondition, PaveFilter, ToolResult } from "../../pave/types.js";

/** A filter condition to add */
interface FilterEntry {
  field: string;
  operator: PaveCondition["operator"];
  value: unknown;
}

/**
 * Build a PAVE filter from optional params.
 * Only includes conditions for params that are not undefined.
 */
export function buildFilter(
  params: Record<string, unknown>,
  mappings: Array<{ param: string; field: string; operator?: PaveCondition["operator"] }>
): PaveFilter | undefined {
  const conditions: FilterEntry[] = [];
  for (const { param, field, operator } of mappings) {
    if (params[param] !== undefined) {
      conditions.push({ field, operator: operator ?? "eq", value: params[param] });
    }
  }
  return conditions.length > 0 ? { operator: "and", conditions } : undefined;
}

/**
 * Build a search filter (wraps value with % for LIKE).
 */
export function buildSearchFilter(
  params: Record<string, unknown>,
  searchParam: string,
  searchField: string,
  extraMappings?: Array<{ param: string; field: string; operator?: PaveCondition["operator"] }>
): PaveFilter | undefined {
  const conditions: FilterEntry[] = [];
  if (params[searchParam] !== undefined) {
    conditions.push({ field: searchField, operator: "like", value: `%${params[searchParam]}%` });
  }
  if (extraMappings) {
    for (const { param, field, operator } of extraMappings) {
      if (params[param] !== undefined) {
        conditions.push({ field, operator: operator ?? "eq", value: params[param] });
      }
    }
  }
  return conditions.length > 0 ? { operator: "and", conditions } : undefined;
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
 */
export const PAGINATION_PROPS = {
  limit: {
    type: "number",
    description: "Maximum number of results to return (optional, default varies by entity)",
  },
  offset: {
    type: "number",
    description: "Number of results to skip for pagination (optional, default 0)",
  },
} as const;

/**
 * Extract pagination params from tool params.
 */
export function getPagination(params: Record<string, unknown>): {
  limit?: number;
  offset?: number;
} {
  const result: { limit?: number; offset?: number } = {};
  if (typeof params.limit === "number") result.limit = params.limit;
  if (typeof params.offset === "number") result.offset = params.offset;
  return result;
}

/**
 * Timezone note for date fields.
 * All date-only fields (YYYY-MM-DD) are interpreted in the org's timezone (America/Denver).
 * All datetime fields must include timezone (ISO 8601 with offset, e.g., 2026-03-25T08:00:00-06:00).
 */
export const TZ_NOTE = "Dates are YYYY-MM-DD in org timezone (America/Denver). " +
  "Datetimes must be ISO 8601 with timezone offset (e.g., 2026-03-25T08:00:00-06:00).";
