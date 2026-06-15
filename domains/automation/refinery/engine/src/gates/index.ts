// Gate registry — Eric's engineering canon as executable gate modules.
//
// Each factory takes the LLM port and returns a GateModule (slice 03's contract).
// makeGateRegistry builds the id→module map the runner resolves manifest gate ids
// through; gateList returns them as the array runPass consumes. A manifest's
// pipeline is the subset of these whose applies() matches the item's traits.

import { GateModule } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { makeStepwiseRefinementGate } from "./stepwise-refinement.js";
import { makePrinciplesCreateGate } from "./principles-create.js";
import { makePrinciplesFixGate } from "./principles-fix.js";
import { makeChestertonsFenceGate } from "./chestertons-fence.js";
import { makeBlastRadiusGate } from "./blast-radius.js";
import { makePremortemGate } from "./premortem.js";
import { makeAdmissionGatesGate } from "./admission-gates.js";

export type GateFactory = (llm: LlmPort) => GateModule;

/** Every discipline gate, in canonical pipeline order. */
export const GATE_FACTORIES: GateFactory[] = [
  makeStepwiseRefinementGate,
  makePrinciplesCreateGate,
  makePrinciplesFixGate,
  makeChestertonsFenceGate,
  makeBlastRadiusGate,
  makePremortemGate,
  makeAdmissionGatesGate,
];

/** Build all gate modules as an ordered array (what runPass consumes). */
export function gateList(llm: LlmPort): GateModule[] {
  return GATE_FACTORIES.map((make) => make(llm));
}

/** Build the id→module registry the runner resolves manifest gate ids through. */
export function makeGateRegistry(llm: LlmPort): Map<string, GateModule> {
  const registry = new Map<string, GateModule>();
  for (const gate of gateList(llm)) {
    registry.set(gate.id, gate);
  }
  return registry;
}

export * from "./llm-port.js";
export * from "./traits.js";
export * from "./verdict.js";
export * from "./stepwise-refinement.js";
export * from "./principles-create.js";
export * from "./principles-fix.js";
export * from "./chestertons-fence.js";
export * from "./blast-radius.js";
export * from "./premortem.js";
export * from "./admission-gates.js";
