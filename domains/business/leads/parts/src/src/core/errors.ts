/**
 * Structured errors for hwc-leads.
 *
 * Mirrors the hwc-notify errors layer — error CLASSES with specific
 * CODES, never bare string messages.
 */

export type ErrorCode =
  | "VALIDATION_ERROR"
  | "HMAC_MISMATCH"
  | "JT_API_ERROR"
  | "POSTGRES_ERROR"
  | "NOTIFY_ERROR"
  | "CONFIG_ERROR"
  | "NOT_FOUND"
  | "INTERNAL_ERROR";

export interface LeadsErrorOpts {
  readonly code: ErrorCode;
  readonly message: string;
  readonly cause?: unknown;
  readonly context?: Record<string, unknown>;
}

export class LeadsError extends Error {
  readonly code: ErrorCode;
  readonly context: Record<string, unknown>;
  readonly cause: unknown;

  constructor(opts: LeadsErrorOpts) {
    super(opts.message);
    this.name = "LeadsError";
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

export function leadsError(code: ErrorCode, message: string, context?: Record<string, unknown>): LeadsError {
  return new LeadsError({ code, message, context });
}
