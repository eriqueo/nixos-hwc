/**
 * Structured error classes for the estimator.
 *
 * Every failure that crosses an engine or trust boundary uses one of these
 * coded subclasses. The `code` field is the stable API — match on it in
 * callers, never on `message`, which is for humans.
 *
 *   SCHEMA_VALIDATION     — a data file failed its Zod contract (Phase A boundary)
 *   UNKNOWN_FORMULA_TOKEN — formula parser saw a token it can't handle
 *   MISSING_TRADE_RATE    — engine asked for a trade rate that isn't defined
 *   JT_PUSH_FAILED        — JT webhook push returned non-2xx / network failure
 */

export class EstimatorError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = 'EstimatorError';
    this.code = code;
    this.details = details;
  }
}

export class SchemaValidationError extends EstimatorError {
  constructor(message, details = {}) {
    super('SCHEMA_VALIDATION', message, details);
    this.name = 'SchemaValidationError';
    this.file = details.file ?? null;
    this.path = details.path ?? null;
    this.issues = details.issues ?? [];
  }
}

export class UnknownFormulaTokenError extends EstimatorError {
  constructor(message, details = {}) {
    super('UNKNOWN_FORMULA_TOKEN', message, details);
    this.name = 'UnknownFormulaTokenError';
  }
}

export class MissingTradeRateError extends EstimatorError {
  constructor(trade, details = {}) {
    super('MISSING_TRADE_RATE', `Unknown trade rate: ${trade}`, { trade, ...details });
    this.name = 'MissingTradeRateError';
    this.trade = trade;
  }
}

export class JtPushError extends EstimatorError {
  constructor(message, details = {}) {
    super('JT_PUSH_FAILED', message, details);
    this.name = 'JtPushError';
    this.status = details.status ?? null;
    this.body = details.body ?? null;
  }
}
