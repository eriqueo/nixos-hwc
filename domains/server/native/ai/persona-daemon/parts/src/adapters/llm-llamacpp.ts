import { LlamaChatResponseSchema, LlamaEmbedResponseSchema } from "../core/types.ts";
import type { ChatPort, EmbedPort } from "../ports/llm.ts";
import { PersonaDaemonError } from "../core/errors.ts";

interface ChatHttpConfig {
  gpuUrl: string;
  cpuUrl: string;
  timeoutMs?: number;   // default 120_000
}

interface EmbedHttpConfig {
  embedUrl: string;
  timeoutMs?: number;   // default 30_000
}

const DEFAULT_CHAT_TIMEOUT = 120_000;
const DEFAULT_EMBED_TIMEOUT = 30_000;

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const ctrl = new AbortController();
  const tid = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } finally {
    clearTimeout(tid);
  }
}

export function createChatHttp(cfg: ChatHttpConfig): ChatPort {
  const timeout = cfg.timeoutMs ?? DEFAULT_CHAT_TIMEOUT;

  return {
    async chat(req) {
      const url = req.backend === "gpu" ? cfg.gpuUrl : cfg.cpuUrl;
      const body = JSON.stringify({
        messages: req.messages,
        temperature: req.temperature,
        top_p: req.topP,
        max_tokens: req.maxTokens,
      });

      let res: Response;
      try {
        res = await fetchWithTimeout(
          `${url}/v1/chat/completions`,
          {
            method: "POST",
            headers: { "content-type": "application/json" },
            body,
          },
          timeout,
        );
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        throw new PersonaDaemonError(
          "CHAT_BACKEND_UNAVAILABLE",
          `chat backend unreachable: ${msg}`,
          { backend: req.backend, endpoint: url },
        );
      }

      if (!res.ok) {
        const text = await res.text().catch(() => "<no body>");
        throw new PersonaDaemonError(
          "CHAT_BACKEND_UNAVAILABLE",
          `chat backend returned ${res.status}`,
          { backend: req.backend, endpoint: url, status: res.status, body: text.slice(0, 500) },
        );
      }

      const json = await res.json().catch(() => {
        throw new PersonaDaemonError(
          "UPSTREAM_PROTOCOL_ERROR",
          "chat backend returned non-JSON body",
          { backend: req.backend },
        );
      });

      const parsed = LlamaChatResponseSchema.safeParse(json);
      if (!parsed.success) {
        throw new PersonaDaemonError(
          "UPSTREAM_PROTOCOL_ERROR",
          "chat backend response failed schema validation",
          { backend: req.backend, issues: parsed.error.issues.slice(0, 5) },
        );
      }

      const choice = parsed.data.choices[0];
      return {
        id: parsed.data.id,
        model: parsed.data.model,
        message: choice.message,
        finishReason: choice.finish_reason,
        promptTokens: parsed.data.usage?.prompt_tokens ?? 0,
        completionTokens: parsed.data.usage?.completion_tokens ?? 0,
      };
    },
  };
}

export function createEmbedHttp(cfg: EmbedHttpConfig): EmbedPort {
  const timeout = cfg.timeoutMs ?? DEFAULT_EMBED_TIMEOUT;
  let cachedDim: number | null = null;

  async function callEmbed(texts: string[]): Promise<Float32Array[]> {
    let res: Response;
    try {
      res = await fetchWithTimeout(
        `${cfg.embedUrl}/v1/embeddings`,
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ input: texts, model: "embed" }),
        },
        timeout,
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      throw new PersonaDaemonError(
        "EMBED_UNAVAILABLE",
        `embed backend unreachable: ${msg}`,
        { endpoint: cfg.embedUrl },
      );
    }

    if (!res.ok) {
      const text = await res.text().catch(() => "<no body>");
      throw new PersonaDaemonError(
        "EMBED_UNAVAILABLE",
        `embed backend returned ${res.status}`,
        { endpoint: cfg.embedUrl, status: res.status, body: text.slice(0, 500) },
      );
    }

    const json = await res.json();
    const parsed = LlamaEmbedResponseSchema.safeParse(json);
    if (!parsed.success) {
      throw new PersonaDaemonError(
        "UPSTREAM_PROTOCOL_ERROR",
        "embed backend response failed schema validation",
        { issues: parsed.error.issues.slice(0, 5) },
      );
    }
    return parsed.data.data
      .slice()
      .sort((a: { index: number }, b: { index: number }) => a.index - b.index)
      .map((d: { embedding: number[] }) => Float32Array.from(d.embedding));
  }

  return {
    embed: callEmbed,
    async dim() {
      if (cachedDim !== null) return cachedDim;
      const [v] = await callEmbed(["dim-probe"]);
      cachedDim = v.length;
      return cachedDim;
    },
  };
}
