// Gate: premortem. Applies to any non-trivial item. Fires at stepwise-refinement's
// Phase-4 review checkpoint. Discipline: ~/.claude/skills/premortem/SKILL.md.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const PremortemVerdictSchema = BaseVerdictSchema.extend({
  killVectors: z.array(
    z.object({
      vector: z.string().min(1),
      severity: z.enum(["low", "medium", "high"]),
    }),
  ),
});
export type PremortemVerdict = z.infer<typeof PremortemVerdictSchema>;

const SPEC = {
  discipline: "premortem",
  source: "~/.claude/skills/premortem/SKILL.md",
  guidance:
    "It is the natural consequence horizon and this item has failed badly. Working " +
    "backward, enumerate the kill vectors that explain the failure across technical, " +
    "integration, and operational domains. Assume failure is real — do not defend the " +
    "plan. Rate each vector's severity.",
  decisionRule:
    "pass if no high-severity vector is left unmitigated; park if a high-severity vector " +
    "needs a human decision before proceeding; fail if a fatal, unavoidable vector exists.",
  shapeHint:
    '{"decision":"pass|park|fail","reason":"...","killVectors":[{"vector":"...","severity":"low|medium|high"}]}',
};

export function makePremortemGate(llm: LlmPort): GateModule {
  return {
    id: "premortem",
    applies: (item: Item) => readTraits(item).trivial !== true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), PremortemVerdictSchema, "premortem");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
