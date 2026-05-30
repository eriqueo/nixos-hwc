import type { ConversationStore, VectorStore } from "../ports/store.ts";
import type { PersonaManifest } from "../core/types.ts";

export interface InternalShellDeps {
  store: ConversationStore;
  vectorStore?: VectorStore;
  personas: PersonaManifest;
  startedAt: number;
  reindex?: (opts?: { full?: boolean; notePath?: string }) => Promise<unknown>;
  reindexLastSuccess?: () => number | null;
}

/**
 * Internal / operational endpoints:
 *   GET  /healthz                  — liveness + counts
 *   GET  /_internal/health         — alias
 *   GET  /_internal/conversations  — list (optional ?persona=, ?limit=)
 *   POST /_internal/conversations  — create (body {persona, title?}); returns {id}
 */
export function createInternalShell(deps: InternalShellDeps) {
  const { store, vectorStore, personas, startedAt, reindex, reindexLastSuccess } = deps;

  return async function handle(req: Request): Promise<Response | null> {
    const url = new URL(req.url);

    if (req.method === "GET" &&
        (url.pathname === "/healthz" || url.pathname === "/_internal/health")) {
      const chunkCount = vectorStore ? await vectorStore.chunkCount() : 0;
      const lastReindex = reindexLastSuccess ? reindexLastSuccess() : null;
      return json(200, {
        status: "ok",
        uptime_s: Math.floor((Date.now() - startedAt) / 1000),
        personas: Object.keys(personas).length,
        vault_chunks: chunkCount,
        reindex_last_success_ts: lastReindex,
        reindex_age_s: lastReindex ? Math.floor((Date.now() - lastReindex) / 1000) : null,
      });
    }

    if (req.method === "POST" && url.pathname === "/_internal/reindex") {
      if (!reindex) {
        return json(503, {
          error: { code: "CONFIG_INVALID", message: "indexer not configured" },
        });
      }
      let body: { full?: boolean; notePath?: string } = {};
      try {
        if (req.headers.get("content-length") !== "0" &&
            req.headers.get("content-type")?.includes("json")) {
          body = await req.json() as typeof body;
        }
      } catch { /* ignore — empty body OK */ }
      // Fire-and-forget so the systemd path unit's curl returns quickly.
      reindex(body).catch(() => { /* logged inside */ });
      return json(202, { accepted: true, full: !!body.full, notePath: body.notePath });
    }

    if (req.method === "GET" && url.pathname === "/_internal/conversations") {
      const personaId = url.searchParams.get("persona") ?? undefined;
      const limit = Number.parseInt(url.searchParams.get("limit") ?? "50", 10);
      const rows = await store.list({ personaId, limit });
      return json(200, { conversations: rows });
    }

    if (req.method === "POST" && url.pathname === "/_internal/conversations") {
      let body: { persona?: string; title?: string };
      try {
        body = await req.json() as { persona?: string; title?: string };
      } catch {
        return json(400, { error: { code: "INVALID_REQUEST", message: "JSON body required" } });
      }
      if (!body.persona || !personas[body.persona]) {
        return json(404, {
          error: {
            code: "PERSONA_UNKNOWN",
            message: `unknown persona: ${body.persona ?? "(missing)"}`,
            detail: { available: Object.keys(personas) },
          },
        });
      }
      const id = await store.create(body.persona, body.title);
      return json(201, { id, persona: body.persona });
    }

    return null;
  };
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
