import type { ChatMessage } from "../core/types.ts";

export interface ChatPort {
  /** Stateless: send messages to a backend, get a response. */
  chat(req: {
    backend: "gpu" | "cpu";
    messages: ChatMessage[];
    temperature: number;
    topP: number;
    maxTokens: number;
  }): Promise<{
    id: string;
    model: string;
    message: ChatMessage;
    finishReason: string | null;
    promptTokens: number;
    completionTokens: number;
  }>;
}

export interface EmbedPort {
  /** Returns one Float32Array per input. */
  embed(texts: string[]): Promise<Float32Array[]>;
  /** Embedding dimensionality (verified once at startup). */
  dim(): Promise<number>;
}
