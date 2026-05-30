import type { ConversationStore, VectorStore } from "../ports/store.ts";
import type { PersonaManifest } from "../core/types.ts";

export interface MetricsSnapshot {
  chatRequestsTotal: Map<string, number>;          // key = persona|backend|status
  chatDurationMsSum: Map<string, number>;          // key = persona|backend
  chatDurationMsCount: Map<string, number>;
  embedRequestsTotal: { ok: number; err: number };
  retrievalChunksReturnedSum: Map<string, number>; // key = persona
  retrievalChunksReturnedCount: Map<string, number>;
  vaultChunksGauge: () => Promise<number>;
  reindexLastSuccessTs: () => number | null;
  conversationsGauge: () => Promise<number>;
  backendUp: () => Promise<Record<string, boolean>>;  // {gpu, cpu, embed}
}

export interface InternalShellDeps {
  store: ConversationStore;
  vectorStore?: VectorStore;
  personas: PersonaManifest;
  startedAt: number;
  reindex?: (opts?: { full?: boolean; notePath?: string }) => Promise<unknown>;
  reindexLastSuccess?: () => number | null;
  metrics?: MetricsSnapshot;
}

/**
 * Internal / operational endpoints:
 *   GET  /healthz                  — liveness + counts
 *   GET  /_internal/health         — alias
 *   GET  /_internal/conversations  — list (optional ?persona=, ?limit=)
 *   POST /_internal/conversations  — create (body {persona, title?}); returns {id}
 */
export function createInternalShell(deps: InternalShellDeps) {
  const { store, vectorStore, personas, startedAt, reindex, reindexLastSuccess, metrics } = deps;

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

    if (req.method === "GET" && url.pathname === "/metrics") {
      if (!metrics) return new Response("# metrics not configured\n", { status: 200 });
      const lines: string[] = [];
      const m = metrics;

      lines.push("# HELP persona_daemon_chat_requests_total Total chat completion requests by persona/backend/status");
      lines.push("# TYPE persona_daemon_chat_requests_total counter");
      for (const [k, v] of m.chatRequestsTotal) {
        const [persona, backend, status] = k.split("|");
        lines.push(`persona_daemon_chat_requests_total{persona="${persona}",backend="${backend}",status="${status}"} ${v}`);
      }

      lines.push("# HELP persona_daemon_chat_duration_seconds_sum Sum of chat completion durations (seconds)");
      lines.push("# TYPE persona_daemon_chat_duration_seconds_sum counter");
      for (const [k, v] of m.chatDurationMsSum) {
        const [persona, backend] = k.split("|");
        lines.push(`persona_daemon_chat_duration_seconds_sum{persona="${persona}",backend="${backend}"} ${(v / 1000).toFixed(3)}`);
      }
      lines.push("# HELP persona_daemon_chat_duration_seconds_count Count of completed chat requests");
      lines.push("# TYPE persona_daemon_chat_duration_seconds_count counter");
      for (const [k, v] of m.chatDurationMsCount) {
        const [persona, backend] = k.split("|");
        lines.push(`persona_daemon_chat_duration_seconds_count{persona="${persona}",backend="${backend}"} ${v}`);
      }

      lines.push("# HELP persona_daemon_embed_requests_total Total embed requests by status");
      lines.push("# TYPE persona_daemon_embed_requests_total counter");
      lines.push(`persona_daemon_embed_requests_total{status="ok"} ${m.embedRequestsTotal.ok}`);
      lines.push(`persona_daemon_embed_requests_total{status="error"} ${m.embedRequestsTotal.err}`);

      lines.push("# HELP persona_daemon_retrieval_chunks_returned_sum Total chunks returned across retrievals");
      lines.push("# TYPE persona_daemon_retrieval_chunks_returned_sum counter");
      for (const [persona, v] of m.retrievalChunksReturnedSum) {
        lines.push(`persona_daemon_retrieval_chunks_returned_sum{persona="${persona}"} ${v}`);
      }
      lines.push("# HELP persona_daemon_retrieval_chunks_returned_count Number of retrieval calls");
      lines.push("# TYPE persona_daemon_retrieval_chunks_returned_count counter");
      for (const [persona, v] of m.retrievalChunksReturnedCount) {
        lines.push(`persona_daemon_retrieval_chunks_returned_count{persona="${persona}"} ${v}`);
      }

      const vaultChunks = await m.vaultChunksGauge();
      lines.push("# HELP persona_daemon_vault_chunks Current count of indexed vault chunks");
      lines.push("# TYPE persona_daemon_vault_chunks gauge");
      lines.push(`persona_daemon_vault_chunks ${vaultChunks}`);

      const conversations = await m.conversationsGauge();
      lines.push("# HELP persona_daemon_conversations Total conversations stored");
      lines.push("# TYPE persona_daemon_conversations gauge");
      lines.push(`persona_daemon_conversations ${conversations}`);

      const last = m.reindexLastSuccessTs();
      lines.push("# HELP persona_daemon_reindex_last_success_timestamp Unix timestamp of last successful reindex (0 if never)");
      lines.push("# TYPE persona_daemon_reindex_last_success_timestamp gauge");
      lines.push(`persona_daemon_reindex_last_success_timestamp ${last ? Math.floor(last / 1000) : 0}`);

      const ups = await m.backendUp();
      lines.push("# HELP persona_daemon_backend_up 1 if backend reachable, 0 otherwise");
      lines.push("# TYPE persona_daemon_backend_up gauge");
      for (const [name, up] of Object.entries(ups)) {
        lines.push(`persona_daemon_backend_up{backend="${name}"} ${up ? 1 : 0}`);
      }

      return new Response(lines.join("\n") + "\n", {
        status: 200,
        headers: { "content-type": "text/plain; version=0.0.4" },
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
