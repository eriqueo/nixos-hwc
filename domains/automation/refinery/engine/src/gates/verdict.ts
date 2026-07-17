// Shared verdict contract + prompt framing for every gate module.
//
// A gate's run() asks the LLM port for a structured verdict. The LLM is a trust
// boundary, so its raw text is parsed against the gate's Zod schema before the
// core touches it (contracts-first). Every gate's verdict extends BaseVerdict
// with { decision, reason }; decide() reads `decision` to map to the runner's
// pass | park | fail.

import { z } from "zod";
import { Item } from "../contracts.js";
import { InvalidGateVerdictError } from "../errors.js";
import { LlmPort } from "./llm-port.js";

export const BaseVerdictSchema = z.object({
  decision: z.enum(["pass", "park", "fail"]),
  reason: z.string().min(1),
  // On park/fail: the specific, concrete decisions/questions the human must
  // resolve to unblock — each a direct, answerable ask, NOT a restatement of the
  // risk. The board renders these as the "to unblock, decide:" checklist so a
  // parked card is actionable instead of a vague refusal. Omitted on pass.
  asks: z.array(z.string().min(1)).optional(),
});
export type BaseVerdict = z.infer<typeof BaseVerdictSchema>;

/**
 * Parse a raw LLM response into a validated verdict. Throws
 * InvalidGateVerdictError (a structured, coded error) if the text isn't JSON or
 * doesn't match the gate's schema — fail loud at the boundary.
 */
export function parseVerdict<T extends z.ZodTypeAny>(
  raw: string,
  schema: T,
  gateId: string,
): z.infer<T> {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch (e) {
    throw new InvalidGateVerdictError(gateId, `response was not JSON: ${(e as Error).message}`);
  }
  const result = schema.safeParse(json);
  if (!result.success) {
    throw new InvalidGateVerdictError(gateId, JSON.stringify(result.error.issues));
  }
  return result.data;
}

/**
 * Ask the LLM for a verdict and parse it — with ONE self-repair round. LLMs
 * routinely return near-miss JSON (an enum synonym like severity "critical"
 * where the schema says low|medium|high — the failure that killed a real run);
 * feeding the validation error back and re-asking recovers most of these.
 * A second miss still fails loud with the structured error.
 */
export async function completeVerdict<T extends z.ZodTypeAny>(
  llm: LlmPort,
  prompt: string,
  schema: T,
  gateId: string,
): Promise<z.infer<T>> {
  const raw = await llm.complete(prompt);
  try {
    return parseVerdict(raw, schema, gateId);
  } catch (e) {
    const repair = [
      prompt,
      "",
      `Your previous response was rejected: ${(e as Error).message}`,
      "Previous response:",
      raw,
      "Respond again with ONLY a corrected JSON object that matches the required shape exactly — fix the reported issues, change nothing else.",
    ].join("\n");
    return parseVerdict(await llm.complete(repair), schema, gateId);
  }
}

export interface GatePromptSpec {
  discipline: string; // human name of the discipline
  source: string; // canon path the discipline is sourced from
  guidance: string; // the discipline, framed as instructions
  decisionRule: string; // when to pass / park / fail
  shapeHint: string; // JSON shape the model must return
}

/** Compose the discipline + the item payload into one LLM prompt. */
export function buildGatePrompt(spec: GatePromptSpec, item: Item): string {
  return [
    `You are applying the "${spec.discipline}" discipline (source: ${spec.source}).`,
    spec.guidance,
    `Evaluate this item (pipeline=${item.pipeline}, step=${item.step}). Payload:`,
    "```json",
    JSON.stringify(item.payload, null, 2),
    "```",
    spec.decisionRule,
    // Make a park/fail actionable, not a vague refusal: force concrete asks.
    'If decision is "park" or "fail", you MUST also include an "asks" array: the ' +
      "specific, concrete decisions or questions the human must answer to unblock " +
      "this — each a direct, answerable ask (e.g. \"Decide: store slides as a single " +
      '.json bundle or per-slide files?"), NOT a restatement of the risk. Omit "asks" on pass.',
    `Respond with ONLY a JSON object, no prose, of this shape: ${spec.shapeHint}`,
  ].join("\n");
}

/** Helper every gate's decide() delegates to: read the validated decision. */
export function decisionOf(output: unknown): "pass" | "park" | "fail" {
  return (output as BaseVerdict).decision;
}
