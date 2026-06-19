// Triage — the intake classifier. A raw sentence has no pipeline yet, so the
// HTTP/CLI intake's first step is this boundary parser (contracts-first):
// classify the sentence into one of the *enabled* pipelines, or "untriaged" if
// none fit confidently. The LLM is the injected LlmPort; the pipeline set is data
// (the enabled pipelines from the catalog), so triage stays substance-agnostic.

import { z } from "zod";
import { Item, ItemTraits } from "./contracts.js";
import { LlmPort } from "./gates/llm-port.js";
import { parseVerdict } from "./gates/verdict.js";

export const UNTRIAGED = "untriaged";

export const TriageResultSchema = z.object({
  pipeline: z.string().min(1),
  confidence: z.number().min(0).max(1),
  reason: z.string().min(1),
});
export type TriageResult = z.infer<typeof TriageResultSchema>;

export interface TriageOption {
  pipeline: string;
  label: string;
}

export interface TriageDecision {
  pipeline: string; // an offered pipeline, or UNTRIAGED
  confidence: number;
  reason: string;
}

const DEFAULT_THRESHOLD = 0.5;

function buildTriagePrompt(text: string, options: TriageOption[]): string {
  const list = options.map((o) => `- ${o.pipeline}: ${o.label}`).join("\n");
  return [
    "Classify the sentence into exactly one of these pipelines, or use",
    `"${UNTRIAGED}" if none fit. Pipelines:`,
    list,
    `Sentence: ${JSON.stringify(text)}`,
    `Respond with ONLY JSON: {"pipeline":"...","confidence":0.0-1.0,"reason":"..."}`,
  ].join("\n");
}

/**
 * Classify a sentence into one of the enabled pipelines. Falls back to UNTRIAGED
 * when the model picks an unoffered pipeline or its confidence is below threshold
 * — the item then parks for human routing on the board.
 */
export async function triageSentence(
  text: string,
  options: TriageOption[],
  llm: LlmPort,
  threshold = DEFAULT_THRESHOLD,
): Promise<TriageDecision> {
  const raw = await llm.complete(buildTriagePrompt(text, options));
  const result = parseVerdict(raw, TriageResultSchema, "triage");
  const offered = new Set(options.map((o) => o.pipeline));
  const ok = offered.has(result.pipeline) && result.confidence >= threshold;
  return {
    pipeline: ok ? result.pipeline : UNTRIAGED,
    confidence: result.confidence,
    reason: result.reason,
  };
}

/** Intake's greenfield default — used when a pipeline declares no defaultTraits. */
const GREENFIELD_TRAITS: ItemTraits = { mode: "greenfield", trivial: false, multiPart: true };

/**
 * Build an Item from a triage decision. A confidently-classified item starts at
 * `firstStep` (its pipeline's first gate) pending; an untriaged item parks at
 * the synthetic `triage` step awaiting human routing.
 *
 * `defaultTraits` is the routed pipeline's declared traits (data-driven): a
 * brownfield pipeline stamps brownfield traits so its fixing-systems gates fire.
 * Omitted (or untriaged) → the greenfield default, preserving prior behavior.
 */
export function makeTriagedItem(
  id: string,
  text: string,
  decision: TriageDecision,
  firstStep: string,
  clock: () => string,
  defaultTraits?: ItemTraits,
): Item {
  const untriaged = decision.pipeline === UNTRIAGED;
  return {
    id,
    pipeline: decision.pipeline,
    step: untriaged ? "triage" : firstStep,
    state: untriaged ? "parked" : "pending",
    parkedReason: untriaged ? `triage: ${decision.reason}` : undefined,
    payload: {
      input: text,
      title: text.length > 80 ? `${text.slice(0, 77)}…` : text,
      triage: { confidence: decision.confidence, reason: decision.reason },
      traits: untriaged ? GREENFIELD_TRAITS : defaultTraits ?? GREENFIELD_TRAITS,
    },
    history: [
      { step: "triage", status: untriaged ? "parked" : "entered", at: clock(), note: decision.reason },
    ],
  };
}
