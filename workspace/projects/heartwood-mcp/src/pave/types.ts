/**
 * PAVE API type definitions.
 *
 * PAVE is JobTread's proprietary query language. It uses HTTP POST with a JSON
 * envelope that specifies the operation (action), entity, fields, filters, etc.
 * Responses always return HTTP 200 — errors are embedded in the response body.
 */

/** Top-level PAVE request envelope */
export interface PaveRequest {
  action: PaveAction;
  entity: string;
  data?: Record<string, unknown>;
  fields?: PaveField[];
  filter?: PaveFilter;
  sort?: PaveSort[];
  limit?: number;
  offset?: number;
  organizationId?: string;
  userId?: string;
  notify?: boolean;
}

export type PaveAction = "create" | "read" | "update" | "delete" | "query";

/** Field selection — can be nested (for related entities) */
export interface PaveField {
  field: string;
  fields?: PaveField[];
  alias?: string;
}

/** Filter conditions */
export interface PaveFilter {
  operator?: "and" | "or";
  conditions?: PaveCondition[];
}

export interface PaveCondition {
  field: string;
  operator:
    | "eq"
    | "neq"
    | "gt"
    | "gte"
    | "lt"
    | "lte"
    | "like"
    | "in"
    | "nin"
    | "null"
    | "notNull";
  value?: unknown;
}

/** Sort specification */
export interface PaveSort {
  field: string;
  direction: "asc" | "desc";
}

/** PAVE API response — always HTTP 200, check for errors */
export interface PaveResponse {
  data?: unknown;
  errors?: PaveError[];
  meta?: {
    total?: number;
    offset?: number;
    limit?: number;
  };
}

export interface PaveError {
  message: string;
  path?: string;
  code?: string;
}

/** Clean result returned to MCP tool callers */
export interface ToolResult<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  code?: string;
  details?: Record<string, unknown>;
}
