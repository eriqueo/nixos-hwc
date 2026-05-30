import {
  type ChatRequest,
  ChatRequestSchema,
  type ChatResponse,
  type PersonaManifest,
  type PersonaMeta,
} from "../core/types.ts";
import type { LogPort } from "../ports/log.ts";
import { httpStatusFor, PersonaDaemonError } from "../core/errors.ts";

export interface OpenAiShellDeps {
  orchestrate: (req: ChatRequest) => Promise<ChatResponse>;
  personas: PersonaManifest;
  log: LogPort;
}

/**
 * Returns a Request handler covering:
 *   POST /v1/chat/completions  — main entry; OpenAI-compatible + extras
 *   GET  /v1/models            — lists personas (so clients see them
 *                                as "models" and can pick one without
 *                                knowing about the `persona` extension)
 */
export function createOpenAiShell(deps: OpenAiShellDeps) {
  const { orchestrate, personas, log } = deps;

  return async function handle(req: Request): Promise<Response | null> {
    const url = new URL(req.url);

    if (req.method === "GET" && url.pathname === "/v1/models") {
      return json(200, {
        object: "list",
        data: Object.values(personas).map((p: PersonaMeta) => ({
          id: p.name,
          object: "model",
          created: 0,
          owned_by: "persona-daemon",
          metadata: {
            backend: p.model,
            description: p.description,
            use_memory: p.useMemory,
            use_knowledge: p.useKnowledge,
          },
        })),
      });
    }

    if (req.method === "POST" && url.pathname === "/v1/chat/completions") {
      let body: unknown;
      try {
        body = await req.json();
      } catch {
        return errorResponse(new PersonaDaemonError(
          "INVALID_REQUEST",
          "request body must be valid JSON",
        ));
      }

      const parsed = ChatRequestSchema.safeParse(body);
      if (!parsed.success) {
        return errorResponse(new PersonaDaemonError(
          "INVALID_REQUEST",
          "request schema validation failed",
          { issues: parsed.error.issues.slice(0, 5) },
        ));
      }

      try {
        const result = await orchestrate(parsed.data);
        return json(200, result);
      } catch (e) {
        if (e instanceof PersonaDaemonError) {
          log.warn("chat.error", { code: e.code, detail: e.detail });
          return errorResponse(e);
        }
        const msg = e instanceof Error ? e.message : String(e);
        log.error("chat.unhandled", { msg });
        return errorResponse(new PersonaDaemonError(
          "CONFIG_INVALID",
          `unhandled error: ${msg}`,
        ));
      }
    }

    return null;  // shell doesn't claim this route
  };
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function errorResponse(e: PersonaDaemonError): Response {
  return json(httpStatusFor(e.code), {
    error: { code: e.code, message: e.message, detail: e.detail },
  });
}
