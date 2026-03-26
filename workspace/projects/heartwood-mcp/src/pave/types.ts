/**
 * PAVE API type definitions.
 *
 * PAVE is JobTread's graph-style query language. Requests are POST to
 * https://api.jobtread.com/pave with a JSON body structured as either a
 * `query` or `mutation` graph, with `$` params for auth and arguments.
 *
 * Query format:
 *   { query: { $: { grantKey }, organization: { $: {}, accounts: { $: { size, where }, nodes: { id: {}, ... } } } } }
 *
 * Mutation format:
 *   { mutation: { $: { grantKey }, createAccount: { $: { name, type }, id: {}, name: {} } } }
 *
 * Responses: { data: { query|mutation: { ... } } } with optional errors: [{ message }]
 */

/** Internal representation of a PAVE operation — used by PaveClient.execute() */
export interface PaveOperation {
  action: PaveAction;
  entity: string;
  data?: Record<string, unknown>;
  fields?: PaveField[];
  filter?: PaveFilter;
  sort?: PaveSort[];
  limit?: number;
  offset?: number;
}

export type PaveAction = "create" | "read" | "update" | "delete" | "query";

/** Field selection — can be nested (for related entities) */
export interface PaveField {
  field: string;
  fields?: PaveField[];
  alias?: string;
}

/** Internal filter representation — converted to PAVE where format when building payload */
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

/** PAVE API HTTP response — check errors first */
export interface PaveResponse {
  data?: unknown;
  errors?: PaveError[];
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

// Keep PaveRequest as an alias for PaveOperation for backwards compatibility
export type PaveRequest = PaveOperation;
