// LlmPort resolver — maps a pipeline's `llmProvider` string to the concrete
// adapter. This is the hexagonal payoff: the gates/executors depend only on
// LlmPort; which model actually answers is data on the pipeline. A pipeline can
// run cheap gate checks on ollama while the execute effector uses claude-cli.

import { LlmPort } from "../gates/llm-port.js";
import { makeClaudeLlm, ClaudeLlmConfig } from "./claude-llm.js";
import { makeAnthropicApiLlm, AnthropicApiConfig } from "./anthropic-api.js";
import { makeOllamaLlm, OllamaConfig } from "./ollama.js";

export type LlmProvider = "claude-cli" | "anthropic-api" | "ollama";

export const LLM_PROVIDERS: LlmProvider[] = ["claude-cli", "anthropic-api", "ollama"];

export interface ResolveLlmOpts {
  claudeCli?: ClaudeLlmConfig;
  anthropicApi?: AnthropicApiConfig;
  ollama?: OllamaConfig;
}

/**
 * Build the LlmPort for a provider key. Defaults to "claude-cli" when the
 * profile omits llmProvider. Throws on an unknown provider (fail loud).
 */
export function resolveLlm(
  provider: string | undefined,
  opts: ResolveLlmOpts = {},
): LlmPort {
  switch (provider ?? "claude-cli") {
    case "claude-cli":
      return makeClaudeLlm(opts.claudeCli);
    case "anthropic-api":
      return makeAnthropicApiLlm(opts.anthropicApi);
    case "ollama":
      return makeOllamaLlm(opts.ollama);
    default:
      throw new Error(
        `unknown llmProvider "${provider}" (expected one of: ${LLM_PROVIDERS.join(", ")})`,
      );
  }
}
