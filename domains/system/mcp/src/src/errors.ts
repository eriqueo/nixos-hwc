/**
 * Structured error helpers for consistent MCP error responses.
 *
 * Every error response includes:
 *   - error_type  — machine-readable category
 *   - message     — human-readable one-liner
 *   - suggestion  — actionable next step for the LLM
 *   - context     — relevant parameters/state (optional)
 *   - error       — raw error string (optional, for stack traces / stderr)
 */

import type { ToolResult, McpErrorType } from "./types.js";

interface McpErrorOpts {
  type: McpErrorType;
  message: string;
  suggestion?: string;
  context?: Record<string, unknown>;
  error?: string;
}

/** Build a structured error ToolResult. */
export function mcpError(opts: McpErrorOpts): ToolResult {
  return {
    status: "error",
    message: opts.message,
    error_type: opts.type,
    suggestion: opts.suggestion,
    ...(opts.context && { context: opts.context }),
    ...(opts.error && { error: opts.error }),
  };
}

/** Wrap a caught exception into a structured error. */
export function catchError(
  type: McpErrorType,
  message: string,
  err: unknown,
  suggestion?: string,
): ToolResult {
  return mcpError({
    type,
    message,
    error: err instanceof Error ? err.message : String(err),
    suggestion,
  });
}
