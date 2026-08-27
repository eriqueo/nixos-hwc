export class RefineryError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "RefineryError";
    this.code = code;
  }
}

export class InvalidPipelineError extends RefineryError {
  readonly issues: unknown;
  constructor(message: string, issues: unknown) {
    super("E_INVALID_PIPELINE", message);
    this.name = "InvalidPipelineError";
    this.issues = issues;
  }
}

export class InvalidGauntletContractError extends RefineryError {
  readonly issues: unknown;
  constructor(message: string, issues: unknown) {
    super("E_INVALID_GAUNTLET_CONTRACT", message);
    this.name = "InvalidGauntletContractError";
    this.issues = issues;
  }
}

export class UnknownGateError extends RefineryError {
  constructor(gateId: string) {
    super("E_UNKNOWN_GATE", `pipeline references unregistered gate: ${gateId}`);
    this.name = "UnknownGateError";
  }
}

export class UnknownStepError extends RefineryError {
  constructor(step: string) {
    super(
      "E_UNKNOWN_STEP",
      `step not present in pipeline gates: ${step}`,
    );
    this.name = "UnknownStepError";
  }
}

/**
 * The headless CLI prints its auth failure to STDOUT and STILL EXITS 0, so
 * exit-code checks read a dead credential as a clean, empty run. That is how
 * the 2026-08-19 OAuth expiry went unnoticed for eight days. Both `claude -p`
 * adapters (ClaudePort in claude-headless.ts, LlmPort in claude-llm.ts) match
 * against this one definition — do not re-spell the signature at a call site.
 */
export const CLAUDE_AUTH_FAILURE_RE = /^Failed to authenticate\. API Error: 40[13]\b/;

/** True when `stdout` is the CLI's auth-failure line. */
export function isClaudeAuthFailure(stdout: string): boolean {
  return CLAUDE_AUTH_FAILURE_RE.test(stdout.trimStart());
}

export class ClaudeAuthError extends RefineryError {
  readonly stdout: string;
  constructor(stdout: string) {
    super(
      "E_CLAUDE_AUTH",
      "claude credential expired or invalid (the CLI reported an auth error and exited 0)",
    );
    this.name = "ClaudeAuthError";
    this.stdout = stdout;
  }
}

export class InvalidGateVerdictError extends RefineryError {
  readonly gateId: string;
  readonly detail: string;
  constructor(gateId: string, detail: string) {
    super(
      "E_INVALID_VERDICT",
      `gate "${gateId}" returned a verdict that failed validation: ${detail}`,
    );
    this.name = "InvalidGateVerdictError";
    this.gateId = gateId;
    this.detail = detail;
  }
}
