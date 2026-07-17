// Gate: principles-create. Applies to greenfield items (builds something new).
// Discipline: ~/.claude/engineering-principles/creating-systems.md.

import { z } from "zod";
import { GateDecision, GateModule, GateVerdict, Item } from "../contracts.js";
import { LlmPort } from "./llm-port.js";
import { readTraits } from "./traits.js";
import { BaseVerdictSchema, buildGatePrompt, completeVerdict, decisionOf } from "./verdict.js";

export const PrinciplesVerdictSchema = BaseVerdictSchema.extend({
  violations: z.array(z.string().min(1)),
});
export type PrinciplesVerdict = z.infer<typeof PrinciplesVerdictSchema>;

const SPEC = {
  discipline: "principles-create",
  source: "~/.claude/engineering-principles/creating-systems.md",
  guidance:
    "Audit the design against the creating-systems canon: (1) hexagonal — core " +
    "knows nothing about HTTP/FS/APIs; (2) data-driven rendering; (3) environment " +
    "agnosticism / late binding; (4) contracts before code (schemas at boundaries); " +
    "(5) declarative over imperative; (6) MCP as integration surface; (7) structured " +
    "errors + observability. List each violation found.",
  decisionRule:
    "pass if no violations; park if a principle can't be assessed from the payload " +
    "(needs more design detail); fail on a hard violation (e.g. core importing a shell).",
  shapeHint: '{"decision":"pass|park|fail","reason":"...","violations":["..."]}',
};

export function makePrinciplesCreateGate(llm: LlmPort): GateModule {
  return {
    id: "principles-create",
    applies: (item: Item) => readTraits(item).mode === "greenfield",
    async run(item: Item): Promise<GateVerdict> {
      const v = await completeVerdict(llm, buildGatePrompt(SPEC, item), PrinciplesVerdictSchema, "principles-create");
      return { verdict: v.reason, output: v };
    },
    decide(verdict: GateVerdict): GateDecision {
      return decisionOf(verdict.output);
    },
  };
}
