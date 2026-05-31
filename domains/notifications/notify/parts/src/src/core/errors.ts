/**
 * Structured errors.
 *
 * Per engineering-principles/creating-systems.md §7: error CLASSES with
 * specific CODES, never bare string messages. Shells map these to HTTP
 * status / MCP error_type; core throws them; adapters wrap upstream
 * failures with context.
 */

export type ErrorCode =
  | "VALIDATION_ERROR"
  | "ROUTING_ERROR"
  | "CHANNEL_FAILURE"
  | "CIRCUIT_OPEN"
  | "AUDIT_WRITE_FAILED"
  | "CONFIG_ERROR"
  | "NOT_FOUND"
  | "INTERNAL_ERROR";

export interface NotifyErrorOpts {
  readonly code: ErrorCode;
  readonly message: string;
  readonly cause?: unknown;
  readonly context?: Record<string, unknown>;
}

export class NotifyError extends Error {
  readonly code: ErrorCode;
  readonly context: Record<string, unknown>;
  readonly cause: unknown;

  constructor(opts: NotifyErrorOpts) {
    super(opts.message);
    this.name = "NotifyError";
    this.code = opts.code;
    this.context = opts.context ?? {};
    this.cause = opts.cause;
  }

  toJSON(): Record<string, unknown> {
    return {
      code: this.code,
      message: this.message,
      context: this.context,
    };
  }
}

/** Convenience for the most common shape. */
export function notifyError(code: ErrorCode, message: string, context?: Record<string, unknown>): NotifyError {
  return new NotifyError({ code, message, context });
}
