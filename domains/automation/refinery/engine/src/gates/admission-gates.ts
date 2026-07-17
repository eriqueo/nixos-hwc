// Gate: admission-gates. Applies to any item before execute. The gauntlet's 8
// admission gates, as one module. Discipline: nightly-builds README (the 8 gates).

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { buildGatePrompt, BaseVerdictSchema, completeVerdict, decisionOf } from "./verdict.js";

export const ADMISSION_GATES = [
  "unattended",
  "self-verifying",
  "goal-addressed",
  "decided-in-advance",
  "inputs-ready",
  "bounded",
  "contained",
  "fails-reviewable",
] as const;

export const AdmissionVerdictSchema = BaseVerdictSchema.extend({
  gates: z.array(
    z.object({
      n: z.number().int().min(1).max(8),
      name: z.string().min(1),
      pass: z.boolean(),
    }),
  ),
});
export type AdmissionVerdict = z.infer<typeof AdmissionVerdictSchema>;

const SPEC = {
  discipline: "admission-gates",
  source: "nightly-builds README — the 8 admission gates",
  guidance:
    "Evaluate the item against the 8 admission gates: (1) Unattended — runs with no " +
    "human mid-flight; (2) Self-verifying — produces a checkable deliverable + report; " +
    "(3) Goal-addressed — maps to a stated goal; (4) Decided in advance — no open " +
    "CONFIRM:/unknowns; (5) Inputs ready — all dependencies present; (6) Bounded — a " +
    "clear done-condition; (7) Contained — blast radius is fenced, no live-system writes; " +
    "(8) Fails reviewable — partial output is reviewable on failure. Report each gate's pass/fail.",
  decisionRule:
    "pass only if all 8 gates pass; park if a gate needs human input (e.g. gate 4 has open " +
    "CONFIRMs, or gate 5 inputs aren't ready); fail if the item is uncontainable (gate 7).",
  shapeHint:
    '{"decision":"pass|park|fail","reason":"...","gates":[{"n":1,"name":"unattended","pass":true}]}',
};

export function makeAdmissionGatesGate(llm: LlmPort): GateModule {
  return {
    id: "admission-gates",
    applies: () => true,
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), AdmissionVerdictSchema, "admission-gates");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
