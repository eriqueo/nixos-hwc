export class RefineryError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "RefineryError";
    this.code = code;
  }
}

export class InvalidManifestError extends RefineryError {
  readonly issues: unknown;
  constructor(message: string, issues: unknown) {
    super("E_INVALID_MANIFEST", message);
    this.name = "InvalidManifestError";
    this.issues = issues;
  }
}

export class UnknownGateError extends RefineryError {
  constructor(gateId: string) {
    super("E_UNKNOWN_GATE", `manifest references unregistered gate: ${gateId}`);
    this.name = "UnknownGateError";
  }
}

export class UnknownStageError extends RefineryError {
  constructor(stage: string) {
    super(
      "E_UNKNOWN_STAGE",
      `stage not present in manifest gates: ${stage}`,
    );
    this.name = "UnknownStageError";
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
