// The outbound port a gate uses to consult an LLM. The engine core knows nothing
// about Claude/OpenAI/etc. — a gate is constructed with whatever adapter fulfills
// this interface (a real headless-claude wrapper in production, a deterministic
// stub in tests). Hexagonal boundary: swap the adapter without touching gates.

export interface LlmPort {
  /** Send a fully-composed prompt, return the model's raw text response. */
  complete(prompt: string): Promise<string>;
}
