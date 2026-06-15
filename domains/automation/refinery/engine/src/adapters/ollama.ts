// Local Ollama LlmPort adapter — raw fetch against a local Ollama daemon's
// /api/generate (non-streaming). For cheap, local, no-API-key gate verdicts.
// Late-bound: base URL + model from the environment.
//
// Note: the heavy execute effector wants a real coding agent (claude-cli), but
// the gate verdicts are small structured JSON — a good fit for a local model.

import { LlmPort } from "../gates/llm-port.js";

export interface OllamaConfig {
  baseUrl?: string; // default $REFINERY_OLLAMA_URL || http://127.0.0.1:11434
  model?: string; // default $REFINERY_OLLAMA_MODEL || "llama3.1"
}

export function makeOllamaLlm(cfg: OllamaConfig = {}): LlmPort {
  const baseUrl =
    cfg.baseUrl ?? process.env.REFINERY_OLLAMA_URL ?? "http://127.0.0.1:11434";
  const model = cfg.model ?? process.env.REFINERY_OLLAMA_MODEL ?? "llama3.1";

  return {
    async complete(prompt: string): Promise<string> {
      const res = await fetch(`${baseUrl}/api/generate`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ model, prompt, stream: false }),
      });
      if (!res.ok) {
        throw new Error(`ollama: HTTP ${res.status} ${await res.text()}`);
      }
      const data = (await res.json()) as { response?: string };
      return data.response ?? "";
    },
  };
}
