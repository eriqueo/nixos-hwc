// Triage — the intake classifier. A raw sentence has no genre yet, so the
// HTTP/CLI intake's first step is this boundary parser (contracts-first):
// classify the sentence into one of the *enabled* profiles, or "untriaged" if
// none fit confidently. The LLM is the injected LlmPort; the genre set is data
// (the enabled profiles from the catalog), so triage stays substance-agnostic.

import { z } from "zod";
import { Item } from "./contracts.js";
import { LlmPort } from "./gates/llm-port.js";
import { parseVerdict } from "./gates/verdict.js";

export const UNTRIAGED = "untriaged";

export const TriageResultSchema = z.object({
  genre: z.string().min(1),
  confidence: z.number().min(0).max(1),
  reason: z.string().min(1),
});
export type TriageResult = z.infer<typeof TriageResultSchema>;

export interface TriageOption {
  genre: string;
  label: string;
}

export interface TriageDecision {
  genre: string; // an offered genre, or UNTRIAGED
  confidence: number;
  reason: string;
}

const DEFAULT_THRESHOLD = 0.5;

function buildTriagePrompt(text: string, options: TriageOption[]): string {
  const list = options.map((o) => `- ${o.genre}: ${o.label}`).join("\n");
  return [
    "Classify the sentence into exactly one of these genres, or use",
    `"${UNTRIAGED}" if none fit. Genres:`,
    list,
    `Sentence: ${JSON.stringify(text)}`,
    `Respond with ONLY JSON: {"genre":"...","confidence":0.0-1.0,"reason":"..."}`,
  ].join("\n");
}

/**
 * Classify a sentence into one of the enabled genres. Falls back to UNTRIAGED
 * when the model picks an unoffered genre or its confidence is below threshold
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
  const offered = new Set(options.map((o) => o.genre));
  const ok = offered.has(result.genre) && result.confidence >= threshold;
  return {
    genre: ok ? result.genre : UNTRIAGED,
    confidence: result.confidence,
    reason: result.reason,
  };
}

/**
 * Build an Item from a triage decision. A confidently-classified item starts at
 * `firstPhase` (its profile's first gate) pending; an untriaged item parks at
 * the synthetic `triage` phase awaiting human routing.
 */
export function makeTriagedItem(
  id: string,
  text: string,
  decision: TriageDecision,
  firstPhase: string,
  clock: () => string,
): Item {
  const untriaged = decision.genre === UNTRIAGED;
  return {
    id,
    genre: decision.genre,
    phase: untriaged ? "triage" : firstPhase,
    phaseStatus: untriaged ? "parked" : "pending",
    parkedReason: untriaged ? `triage: ${decision.reason}` : undefined,
    payload: {
      input: text,
      title: text.length > 80 ? `${text.slice(0, 77)}…` : text,
      triage: { confidence: decision.confidence, reason: decision.reason },
      traits: { mode: "greenfield", trivial: false, multiPart: true },
    },
    history: [
      { phase: "triage", status: untriaged ? "parked" : "entered", at: clock(), note: decision.reason },
    ],
  };
}
