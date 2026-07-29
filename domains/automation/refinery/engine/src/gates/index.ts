// Gate registry — Eric's engineering canon as executable gate modules.
//
// Each factory takes the LLM port and returns a GateModule (slice 03's contract).
// makeGateRegistry builds the id→module map the runner resolves profile gate ids
// through; gateList returns them as the array runPass consumes. A profile's
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
import { makeTemporaryTrackedGate } from "./temporary-tracked.js";
import { makeBoundedCapacityGate } from "./bounded-capacity.js";
import { makeEffectCategoryGate } from "./effect-category.js";
import { makeWiredOrLabeledGate } from "./wired-or-labeled.js";
import { makePromotionRuleGate } from "./promotion-rule.js";
import { makeSessionOutputRoutedGate } from "./session-output-routed.js";

export type GateFactory = (llm: LlmPort) => GateModule;

/** Every discipline gate, in canonical pipeline order. The rev 3 governing
 *  cluster (2026-07-29 backlog burn-down) appends after the original seven;
 *  a gate only fires for pipelines that list its id, so registration alone
 *  changes no live pipeline. */
export const GATE_FACTORIES: GateFactory[] = [
  makeStepwiseRefinementGate,
  makePrinciplesCreateGate,
  makePrinciplesFixGate,
  makeChestertonsFenceGate,
  makeBlastRadiusGate,
  makePremortemGate,
  makeAdmissionGatesGate,
  makeTemporaryTrackedGate,
  makeBoundedCapacityGate,
  makeEffectCategoryGate,
  makeWiredOrLabeledGate,
  makePromotionRuleGate,
  makeSessionOutputRoutedGate,
];

/** Build all gate modules as an ordered array (what runPass consumes). */
export function gateList(llm: LlmPort): GateModule[] {
  return GATE_FACTORIES.map((make) => make(llm));
}

/** Build the id→module registry the runner resolves profile gate ids through. */
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
export * from "./temporary-tracked.js";
export * from "./bounded-capacity.js";
export * from "./effect-category.js";
export * from "./wired-or-labeled.js";
export * from "./promotion-rule.js";
export * from "./session-output-routed.js";
