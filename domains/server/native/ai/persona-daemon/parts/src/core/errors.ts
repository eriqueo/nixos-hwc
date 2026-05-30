export const ERROR_CODES = [
  "CONFIG_INVALID",
  "PERSONA_UNKNOWN",
  "CONVERSATION_NOT_FOUND",
  "CHAT_BACKEND_UNAVAILABLE",
  "EMBED_UNAVAILABLE",
  "VAULT_WRITER_UNAVAILABLE",
  "STORE_BUSY",
  "SUMMARIZATION_FAILED",
  "REINDEX_IN_PROGRESS",
  "INVALID_REQUEST",
  "UPSTREAM_PROTOCOL_ERROR",
] as const;

export type ErrorCode = typeof ERROR_CODES[number];

export class PersonaDaemonError extends Error {
  override readonly name = "PersonaDaemonError";
  readonly code: ErrorCode;
  readonly detail?: Record<string, unknown>;

  constructor(code: ErrorCode, message: string, detail?: Record<string, unknown>) {
    super(message);
    this.code = code;
    this.detail = detail;
  }

  toJSON(): { code: ErrorCode; message: string; detail?: Record<string, unknown> } {
    return { code: this.code, message: this.message, detail: this.detail };
  }
}

const HTTP_STATUS: Record<ErrorCode, number> = {
  CONFIG_INVALID: 500,
  PERSONA_UNKNOWN: 404,
  CONVERSATION_NOT_FOUND: 404,
  CHAT_BACKEND_UNAVAILABLE: 503,
  EMBED_UNAVAILABLE: 503,
  VAULT_WRITER_UNAVAILABLE: 503,
  STORE_BUSY: 503,
  SUMMARIZATION_FAILED: 500,
  REINDEX_IN_PROGRESS: 409,
  INVALID_REQUEST: 400,
  UPSTREAM_PROTOCOL_ERROR: 502,
};

export function httpStatusFor(code: ErrorCode): number {
  return HTTP_STATUS[code];
}
