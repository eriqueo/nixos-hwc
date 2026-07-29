// Gate: wired-or-labeled. Applies to non-trivial items.
// Discipline: ~/.claude/engineering-principles/engineering-principles.md,
// Part III (Governing) — R4, Enforced or Guideline — Nothing in Between.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const WiredOrLabeledVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type WiredOrLabeledVerdict = z.infer<typeof WiredOrLabeledVerdictSchema>;

const SPEC = {
  discipline: "wired-or-labeled",
  source: "~/.claude/engineering-principles/engineering-principles.md (Part III — R4, Enforced or Guideline)",
  guidance:
    "If the change introduces a rule, standard, or convention, it must either " +
    "ship a mechanical check (lint, flake check, hook, test) or be explicitly " +
    "labeled a guideline — prose that pretends to be enforcement is neither, and " +
    "an always-red or never-run check is worse than none. Lint the lints: a new " +
    "check must be seeded with a deliberate violation once (watch it fail, then " +
    "restore) and must never match its own definition. List each rule that is " +
    "neither wired nor labeled, and each new check with no seeded-red evidence.",
  decisionRule:
    "pass if every new rule is wired or explicitly labeled a guideline (or the " +
    "change adds no rules); park if it's unclear whether a statement is meant as " +
    "an enforced rule; fail on a rule presented as enforced with no check behind " +
    "it.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makeWiredOrLabeledGate(llm: LlmPort): GateModule {
  return {
    id: "wired-or-labeled",
    applies: (item: Item) => readTraits(item).trivial !== true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), WiredOrLabeledVerdictSchema, "wired-or-labeled");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
