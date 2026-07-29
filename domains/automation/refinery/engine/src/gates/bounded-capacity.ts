// Gate: bounded-capacity. Applies to non-trivial items (greenfield designs and
// brownfield changes can both add unbounded growth).
// Discipline: ~/.claude/engineering-principles/engineering-principles.md,
// Part II — Principle 13, Bounded Capacity.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const BoundedCapacityVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type BoundedCapacityVerdict = z.infer<typeof BoundedCapacityVerdictSchema>;

const SPEC = {
  discipline: "bounded-capacity",
  source: "~/.claude/engineering-principles/engineering-principles.md (Part II — Principle 13, Bounded Capacity)",
  guidance:
    "Everything that grows needs an explicit limit and a designed behavior at " +
    "the limit. Flow: every queue, buffer, pool, retry loop, and fan-out gets a " +
    "bound and a chosen at-limit behavior (block, shed, or dead-letter); retries " +
    "get a ceiling and jitter; fan-out gets a concurrency cap. State: every " +
    "persistent store declares its retention class — CRITICAL (indefinite, " +
    "backed up), REPLACEABLE (rebuildable from source of truth), or AUTO-MANAGED " +
    "(time/size-bounded with a fail-safe). An unbounded channel is a memory leak " +
    "with a vocabulary. List each unbounded growth point found.",
  decisionRule:
    "pass if every growth point has a stated bound and at-limit behavior (or " +
    "none exist); park if capacity behavior can't be assessed from the payload; " +
    "fail on an unbounded queue/retry/fan-out or a persistent store with no " +
    "retention class.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makeBoundedCapacityGate(llm: LlmPort): GateModule {
  return {
    id: "bounded-capacity",
    applies: (item: Item) => readTraits(item).trivial !== true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), BoundedCapacityVerdictSchema, "bounded-capacity");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
