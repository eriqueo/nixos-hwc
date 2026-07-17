// Gate: blast-radius. Applies to brownfield items in write-mode execution.
// Discipline: fixing-systems #2 — map every reference/dependency before changing.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const BlastRadiusVerdictSchema = BaseVerdictSchema.extend({
  references: z.array(z.string().min(1)),
});
export type BlastRadiusVerdict = z.infer<typeof BlastRadiusVerdictSchema>;

const SPEC = {
  discipline: "blast-radius",
  source: "~/.claude/engineering-principles/fixing-systems.md (#2)",
  guidance:
    "Before a single line changes, enumerate everywhere its effects are felt: every " +
    "caller, dependent, and shared utility the change touches. Assume every change has " +
    "side effects until proven otherwise. List the references/dependencies affected.",
  decisionRule:
    "pass if the blast radius is bounded and enumerated; park if references can't be " +
    "fully mapped from the payload (needs a repo-wide search); fail if the change ripples " +
    "into load-bearing shared code without a containment plan.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","references":["path:line","..."]}',
};

export function makeBlastRadiusGate(llm: LlmPort): GateModule {
  return {
    id: "blast-radius",
    applies: (item: Item) => {
      const t = readTraits(item);
      return t.mode === "brownfield" && t.writeMode === true;
    },
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), BlastRadiusVerdictSchema, "blast-radius");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
