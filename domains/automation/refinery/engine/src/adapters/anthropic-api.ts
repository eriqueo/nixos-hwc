// Anthropic Messages API LlmPort adapter — raw fetch, no SDK dependency (keeps
// the engine's dep surface to zod + yaml). One non-streaming completion per
// call: send the prompt as a single user message, return the concatenated text
// blocks. Late-bound: API key + model from the environment.
//
// Model defaults to claude-opus-4-8 (current most-capable). Gate verdicts are
// small structured JSON, so a cheaper model (claude-haiku-4-5) is a reasonable
// override via REFINERY_ANTHROPIC_MODEL / cfg.model.

import { LlmPort } from "../gates/llm-port.js";

export interface AnthropicApiConfig {
  apiKey?: string; // default: $REFINERY_ANTHROPIC_API_KEY || $ANTHROPIC_API_KEY
  model?: string; // default: $REFINERY_ANTHROPIC_MODEL || "claude-opus-4-8"
  maxTokens?: number; // default 4096 (verdicts are small)
  baseUrl?: string; // default https://api.anthropic.com
}

interface AnthropicTextBlock {
  type: string;
  text?: string;
}

export function makeAnthropicApiLlm(cfg: AnthropicApiConfig = {}): LlmPort {
  const apiKey =
    cfg.apiKey ?? process.env.REFINERY_ANTHROPIC_API_KEY ?? process.env.ANTHROPIC_API_KEY;
  const model = cfg.model ?? process.env.REFINERY_ANTHROPIC_MODEL ?? "claude-opus-4-8";
  const maxTokens = cfg.maxTokens ?? 4096;
  const baseUrl = cfg.baseUrl ?? "https://api.anthropic.com";

  return {
    async complete(prompt: string): Promise<string> {
      if (!apiKey) {
        throw new Error(
          "anthropic-api: no API key (set REFINERY_ANTHROPIC_API_KEY or ANTHROPIC_API_KEY)",
        );
      }
      const res = await fetch(`${baseUrl}/v1/messages`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model,
          max_tokens: maxTokens,
          messages: [{ role: "user", content: prompt }],
        }),
      });
      if (!res.ok) {
        throw new Error(`anthropic-api: HTTP ${res.status} ${await res.text()}`);
      }
      const data = (await res.json()) as { content?: AnthropicTextBlock[] };
      return (data.content ?? [])
        .filter((b) => b.type === "text" && typeof b.text === "string")
        .map((b) => b.text as string)
        .join("");
    },
  };
}
