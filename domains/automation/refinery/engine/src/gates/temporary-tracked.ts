// Gate: temporary-tracked. Applies to non-trivial items (a trivial rename
// doesn't introduce shims).
// Discipline: ~/.claude/engineering-principles/engineering-principles.md,
// Part III (Governing) — R5, Temporary Means Tracked.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const TemporaryTrackedVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type TemporaryTrackedVerdict = z.infer<typeof TemporaryTrackedVerdictSchema>;

const SPEC = {
  discipline: "temporary-tracked",
  source: "~/.claude/engineering-principles/engineering-principles.md (Part III — R5, Temporary Means Tracked)",
  guidance:
    "Audit the change for temporary artifacts: every shim, pin, wrapper, " +
    "workaround, feature flag, and principle exception must carry an annotation " +
    "with its reason AND its removal condition — ideally a checkable predicate " +
    "(e.g. 'remove when channel tailscale >= 1.98.2') — or be explicitly marked " +
    "'permanent by design'. An untracked temporary thing is permanent cruft. " +
    "List each untracked temporary artifact found.",
  decisionRule:
    "pass if every temporary artifact is annotated (or none exist); park if the " +
    "payload doesn't show enough of the change to tell; fail if a " +
    "shim/pin/workaround lands with no reason + removal condition.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makeTemporaryTrackedGate(llm: LlmPort): GateModule {
  return {
    id: "temporary-tracked",
    applies: (item: Item) => readTraits(item).trivial !== true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), TemporaryTrackedVerdictSchema, "temporary-tracked");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
