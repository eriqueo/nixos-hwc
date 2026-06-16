/**
 * Structured error classes for the estimator.
 *
 * Every failure that crosses an engine or trust boundary uses one of these
 * coded subclasses. The `code` field is the stable API — match on it in
 * callers, never on `message`, which is for humans.
 */

export type EstimatorErrorCode =
  | 'SCHEMA_VALIDATION'
  | 'UNKNOWN_FORMULA_TOKEN'
  | 'MISSING_TRADE_RATE'
  | 'JT_PUSH_FAILED';

export class EstimatorError extends Error {
  readonly code: EstimatorErrorCode;
  readonly details: Record<string, unknown>;
  constructor(code: EstimatorErrorCode, message: string, details: Record<string, unknown> = {}) {
    super(message);
    this.name = 'EstimatorError';
    this.code = code;
    this.details = details;
  }
}

export interface SchemaIssue {
  path: (string | number)[];
  message: string;
  code?: string;
}

export class SchemaValidationError extends EstimatorError {
  readonly file: string | null;
  readonly path: string | null;
  readonly issues: SchemaIssue[];
  constructor(message: string, details: { file?: string; path?: string; issues?: SchemaIssue[] } = {}) {
    super('SCHEMA_VALIDATION', message, details as Record<string, unknown>);
    this.name = 'SchemaValidationError';
    this.file = details.file ?? null;
    this.path = details.path ?? null;
    this.issues = details.issues ?? [];
  }
}

export class UnknownFormulaTokenError extends EstimatorError {
  constructor(message: string, details: Record<string, unknown> = {}) {
    super('UNKNOWN_FORMULA_TOKEN', message, details);
    this.name = 'UnknownFormulaTokenError';
  }
}

export class MissingTradeRateError extends EstimatorError {
  readonly trade: string;
  constructor(trade: string, details: Record<string, unknown> = {}) {
    super('MISSING_TRADE_RATE', `Unknown trade rate: ${trade}`, { trade, ...details });
    this.name = 'MissingTradeRateError';
    this.trade = trade;
  }
}

export class JtPushError extends EstimatorError {
  readonly status: number | null;
  readonly body: string | null;
  constructor(message: string, details: { status?: number | null; body?: string | null; cause?: unknown } = {}) {
    super('JT_PUSH_FAILED', message, details as Record<string, unknown>);
    this.name = 'JtPushError';
    this.status = details.status ?? null;
    this.body = details.body ?? null;
  }
}
