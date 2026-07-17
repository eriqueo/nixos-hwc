// Gate: stepwise-refinement. Applies to non-trivial / multi-part items.
// Discipline: decompose (P1) → refine each part (P2) → integrate (P3) → review (P4).

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const StepwiseVerdictSchema = BaseVerdictSchema.extend({
  steps: z.array(z.string().min(1)).min(1),
});
export type StepwiseVerdict = z.infer<typeof StepwiseVerdictSchema>;

const SPEC = {
  discipline: "stepwise-refinement",
  source: "stepwise-refinement method (P1 decompose → P2 refine → P3 integrate → P4 review)",
  guidance:
    "Decompose the item into an ordered list of independently-shippable steps. " +
    "Confirm each step can be refined and integrated in isolation and that a " +
    "review checkpoint exists before anything ships.",
  decisionRule:
    "pass if it decomposes cleanly into ordered steps; park if a step hides " +
    "unknowns or needs human input; fail if the work is too incoherent to decompose.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","steps":["step 1","step 2"]}',
};

export function makeStepwiseRefinementGate(llm: LlmPort): GateModule {
  return {
    id: "stepwise-refinement",
    applies: (item: Item) => readTraits(item).trivial !== true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), StepwiseVerdictSchema, "stepwise-refinement");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
