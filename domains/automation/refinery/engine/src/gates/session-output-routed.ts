// Gate: session-output-routed. Applies to write-mode items (the ones that
// land reports, plans, and scratch artifacts).
// Discipline: ~/.claude/engineering-principles/engineering-principles.md,
// Part III (Governing) — R8, Ephemeral Until Promoted.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const SessionOutputRoutedVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type SessionOutputRoutedVerdict = z.infer<typeof SessionOutputRoutedVerdictSchema>;

const SPEC = {
  discipline: "session-output-routed",
  source: "~/.claude/engineering-principles/engineering-principles.md (Part III — R8, Ephemeral Until Promoted)",
  guidance:
    "Session and agent output (reports, plans, analyses, scratch files) is " +
    "ephemeral until merged into the one living document for its topic — then " +
    "the scratch is deleted, not archived. Archive means move, never copy: a " +
    "file exists in archive or outside it, never both. Check that the change " +
    "states where each output it produces lands: merged into a living doc, or " +
    "deleted; nothing parked in the tree, nothing copy-archived. A report " +
    "sitting unmerged three weeks later is cruft. List each output with no " +
    "stated merge-or-delete destination.",
  decisionRule:
    "pass if every produced output has a merge-or-delete destination (or none " +
    "are produced); park if output routing can't be determined from the " +
    "payload; fail if a report/plan is parked in the tree or copied into an " +
    "archive.",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makeSessionOutputRoutedGate(llm: LlmPort): GateModule {
  return {
    id: "session-output-routed",
    applies: (item: Item) => readTraits(item).writeMode === true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), SessionOutputRoutedVerdictSchema, "session-output-routed");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
