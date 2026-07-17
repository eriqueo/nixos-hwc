// The project-ideation pipeline's `integrate` executor: synthesize a developed
// project spec from the item (which has already passed the gate pipeline) and
// write it to a scratch dir. No code execution — for this pipeline `integrate`
// just writes the spec (later: fold to brain).
//
// The spec is a contract (Zod). The LLM port produces it from the item + its
// gate history; the result is validated before rendering, so a malformed spec
// fails loud rather than writing half a document.

import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import { Item, Executor, ExecutorResult } from "../contracts.js";
import { LlmPort } from "../gates/llm-port.js";
import { completeVerdict } from "../gates/verdict.js";

export const SpecSchema = z.object({
  goal: z.string().min(1),
  steps: z.array(z.string().min(1)).min(1),
  principlesAudit: z.array(z.string().min(1)),
  killVectors: z.array(
    z.object({ vector: z.string().min(1), severity: z.enum(["low", "medium", "high"]) }),
  ),
  deliverable: z.string().min(1),
});
export type Spec = z.infer<typeof SpecSchema>;

/** The section headings a complete spec must contain, in order. */
export const SPEC_SECTIONS = [
  "Goal",
  "Decomposed steps",
  "Principles self-audit",
  "Premortem kill-vectors",
  "Deliverable",
] as const;

export function specToMarkdown(spec: Spec): string {
  const kv = spec.killVectors.length
    ? spec.killVectors.map((k) => `- [${k.severity}] ${k.vector}`).join("\n")
    : "- (none surfaced)";
  return [
    `# Project spec: ${spec.goal}`,
    "",
    "## Goal",
    spec.goal,
    "",
    "## Decomposed steps",
    spec.steps.map((s, i) => `${i + 1}. ${s}`).join("\n"),
    "",
    "## Principles self-audit",
    spec.principlesAudit.length
      ? spec.principlesAudit.map((a) => `- ${a}`).join("\n")
      : "- (clean — no violations)",
    "",
    "## Premortem kill-vectors",
    kv,
    "",
    "## Deliverable",
    spec.deliverable,
    "",
  ].join("\n");
}

/** True if every required section heading is present (the section-completeness check). */
export function isSpecComplete(markdown: string): boolean {
  return SPEC_SECTIONS.every((h) => markdown.includes(`## ${h}`));
}

const SPEC_PROMPT = (item: Item) =>
  [
    "Synthesize a developed project spec from the item below, which has passed the",
    "scope / principles / premortem gates. Produce JSON with: goal (string), steps",
    "(string[]), principlesAudit (string[] of how the design honors the engineering",
    "principles), killVectors ([{vector,severity}]), deliverable (string).",
    "Item:",
    "```json",
    JSON.stringify(item.payload, null, 2),
    "```",
    "Respond with ONLY the JSON object.",
  ].join("\n");

export interface WriteSpecConfig {
  scratchDir: string;
}

export function makeSpecExecutor(
  cfg: WriteSpecConfig,
  llm: LlmPort,
): Executor {
  return {
    id: "spec",
    async run(item: Item): Promise<ExecutorResult> {
      const spec = await completeVerdict(llm, SPEC_PROMPT(item), SpecSchema, "spec");
      const markdown = specToMarkdown(spec);
      mkdirSync(cfg.scratchDir, { recursive: true });
      const specPath = join(cfg.scratchDir, `${item.id}-spec.md`);
      writeFileSync(specPath, markdown);
      return {
        outcome: "succeeded",
        verdict: "spec-written",
        reportPresent: true,
        branch: null,
        pristine: null,
        pushed: false,
        detail: `wrote project spec to ${specPath}`,
        output: { specPath, spec },
      };
    },
  };
}
