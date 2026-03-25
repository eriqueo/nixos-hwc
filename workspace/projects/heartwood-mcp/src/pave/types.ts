/**
 * PAVE API type definitions.
 *
 * PAVE is JobTread's proprietary query language. ALL requests are POST to
 * https://api.jobtread.com/pave with auth in the request body (grantKey),
 * NOT as a Bearer token header.
 *
 * Operations are named keys (createAccount, updateAccount, organization, node, etc.)
 * nested inside a `query` envelope. Fields to return are nested empty objects.
 * Responses always return HTTP 200 — errors are embedded in the response body.
 */

/** PAVE query envelope — all requests use this format */
export interface PaveQuery {
  query: {
    $: PaveAuth;
    [operationName: string]: unknown;
  };
}

export interface PaveAuth {
  grantKey: string;
  notify?: boolean;
  viaUserId?: string;
}

/** Fields to return — nested empty objects */
export interface PaveFields {
  [key: string]: PaveFields | Record<string, never>;
}

/** PAVE where clause for queries */
export type PaveWhere = {
  and?: PaveWhereCondition[][];
  or?: PaveWhereCondition[][];
};

/** [field, operator, value] shorthand */
export type PaveWhereCondition = [string, string, unknown];

/** PAVE API response — always HTTP 200, check for errors */
export interface PaveResponse {
  [key: string]: unknown;
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
