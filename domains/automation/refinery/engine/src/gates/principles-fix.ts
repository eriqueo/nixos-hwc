// Gate: principles-fix. Applies to brownfield items (modifies what exists).
// Discipline: ~/.claude/engineering-principles/fixing-systems.md.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const PrinciplesFixVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type PrinciplesFixVerdict = z.infer<typeof PrinciplesFixVerdictSchema>;

const SPEC = {
  discipline: "principles-fix",
  source: "~/.claude/engineering-principles/fixing-systems.md",
  guidance:
    "Audit the change against the fixing-systems canon: (1) Chesterton's Fence — " +
    "understand why the code exists before touching it; (2) blast-radius — map every " +
    "reference affected; (3) seek the precedent — reuse the codebase's existing " +
    "patterns/helpers; (4) eliminate environment coupling; (5) minimum viable fix — " +
    "smallest diff, no bundled refactors. List each violation found.",
  decisionRule:
    "pass if the change respects all five; park if intent or blast radius is unclear " +
    "(needs investigation); fail if it bundles unrelated refactors or rewrites working code.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makePrinciplesFixGate(llm: LlmPort): GateModule {
  return {
    id: "principles-fix",
    applies: (item: Item) => readTraits(item).mode === "brownfield",
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), PrinciplesFixVerdictSchema, "principles-fix");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
