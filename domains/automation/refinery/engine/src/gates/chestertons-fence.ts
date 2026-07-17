// Gate: chestertons-fence. Applies when the item touches code it didn't write.
// Discipline: ~/.claude/skills/chestertons-fence/SKILL.md.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const FenceVerdictSchema = BaseVerdictSchema.extend({
  hypotheses: z.array(z.string().min(1)),
});
export type FenceVerdict = z.infer<typeof FenceVerdictSchema>;

const SPEC = {
  discipline: "chestertons-fence",
  source: "~/.claude/skills/chestertons-fence/SKILL.md",
  guidance:
    "Before endorsing any change to existing code: (1) observe what the code does, " +
    "touches, and what's surprising — as facts, not opinions; (2) reconstruct intent " +
    "with at least two hypotheses (designed / evolved / defensive) for each surprising " +
    "element; (3) map the dependency graph. List the intent hypotheses you formed.",
  decisionRule:
    "pass if the author's intent is understood well enough to change safely; park if " +
    "intent is unknown and needs investigation (git blame, tests, asking); fail only if " +
    "the change provably breaks a load-bearing invariant.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","hypotheses":["..."]}',
};

export function makeChestertonsFenceGate(llm: LlmPort): GateModule {
  return {
    id: "chestertons-fence",
    applies: (item: Item) => readTraits(item).touchesExistingCode === true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), FenceVerdictSchema, "chestertons-fence");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
