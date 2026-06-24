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
