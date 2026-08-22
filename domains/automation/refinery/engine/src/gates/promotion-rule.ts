// Gate: promotion-rule. Applies to write-mode items (only landed diffs can
// duplicate sibling lines).
// Discipline: ~/.claude/engineering-principles.md,
// Part II — Principle 10, Layers with a Promotion Rule.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const PromotionRuleVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type PromotionRuleVerdict = z.infer<typeof PromotionRuleVerdictSchema>;

const SPEC = {
  discipline: "promotion-rule",
  source: "~/.claude/engineering-principles.md (Part II — Principle 10, Layers with a Promotion Rule)",
  guidance:
    "A line a second instance would copy verbatim belongs one layer up. If this " +
    "change copies lines from a same-layer sibling (a second machine file, " +
    "second container module, second config), the shared content must be " +
    "promoted to the layer above (role, domain, shared lib, base template) " +
    "instead of duplicated — the second copy is the promotion signal, not a " +
    "style question. Instance layers hold only genuine one-offs. List each " +
    "verbatim-copied block and where it should be promoted to.",
  decisionRule:
    "pass if nothing is copied verbatim from a same-layer sibling; park if " +
    "sibling context isn't visible in the payload; fail if the change " +
    "duplicates sibling lines that a promotion would share.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makePromotionRuleGate(llm: LlmPort): GateModule {
  return {
    id: "promotion-rule",
    applies: (item: Item) => readTraits(item).writeMode === true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), PromotionRuleVerdictSchema, "promotion-rule");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
