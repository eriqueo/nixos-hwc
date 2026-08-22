// Gate: effect-category. Applies to non-trivial items.
// Discipline: ~/.claude/engineering-principles.md,
// Part II — Principle 14, Effects Are Idempotent, Keyed, or Marked.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const EffectCategoryVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type EffectCategoryVerdict = z.infer<typeof EffectCategoryVerdictSchema>;

const SPEC = {
  discipline: "effect-category",
  source: "~/.claude/engineering-principles.md (Part II — Principle 14, Effects Are Idempotent, Keyed, or Marked)",
  guidance:
    "Every externally visible effect (email, API mutation, payment, file write) " +
    "must be classified as exactly one of three things, decided before any retry " +
    "loop exists: (1) naturally idempotent — twice equals once by construction; " +
    "(2) keyed — an idempotency key, reservation row, or create-fails-on-exists " +
    "makes the second attempt a no-op, reserved BEFORE the effect fires; or (3) " +
    "explicitly non-retriable — marked, kept out of every retry loop, failure " +
    "surfaced loud. The unacceptable state is the unexamined fourth: an effect " +
    "that might retry and might double-fire. After creating an object in an " +
    "eventually-consistent external system, the created ID is published through " +
    "your own consistent store, not re-queried. List each unclassified effect.",
  decisionRule:
    "pass if every external effect is classified into one of the three " +
    "categories (or none exist); park if effects can't be identified from the " +
    "payload; fail on an effect reachable from a retry path with no idempotency " +
    "story.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makeEffectCategoryGate(llm: LlmPort): GateModule {
  return {
    id: "effect-category",
    applies: (item: Item) => readTraits(item).trivial !== true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), EffectCategoryVerdictSchema, "effect-category");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
