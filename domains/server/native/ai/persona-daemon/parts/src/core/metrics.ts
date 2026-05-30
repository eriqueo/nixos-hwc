// In-process Prometheus metrics. Hand-written exposition (no client lib):
// the surface area is small enough that the deserved cost of a npm/jsr dep
// + version drift outweighs the convenience.

import type { ConversationStore, VectorStore } from "../ports/store.ts";
import type { MetricsSnapshot } from "../shells/http-internal.ts";

export interface MetricsWriter {
  recordChat(args: {
    persona: string;
    backend: string;
    status: "ok" | "error";
    durationMs: number;
    retrievalChunks: number;
  }): void;
  recordEmbed(status: "ok" | "error"): void;
  recordBackendProbe(name: string, up: boolean): void;
  lastReindexSuccess(ts: number | null): void;
}

export function createMetrics(args: {
  store: ConversationStore;
  vectorStore?: VectorStore;
  backendUrls: { gpu: string; cpu: string; embed: string };
}): { writer: MetricsWriter; snapshot: MetricsSnapshot } {
  const chatRequestsTotal = new Map<string, number>();
  const chatDurationMsSum = new Map<string, number>();
  const chatDurationMsCount = new Map<string, number>();
  const embedRequestsTotal = { ok: 0, err: 0 };
  const retrievalSum = new Map<string, number>();
  const retrievalCount = new Map<string, number>();
  let lastReindexTs: number | null = null;
  const backendCache: Record<string, boolean> = { gpu: false, cpu: false, embed: false };

  const inc = (m: Map<string, number>, k: string, by = 1) => {
    m.set(k, (m.get(k) ?? 0) + by);
  };

  const writer: MetricsWriter = {
    recordChat({ persona, backend, status, durationMs, retrievalChunks }) {
      inc(chatRequestsTotal, `${persona}|${backend}|${status}`);
      inc(chatDurationMsSum, `${persona}|${backend}`, durationMs);
      inc(chatDurationMsCount, `${persona}|${backend}`);
      if (retrievalChunks > 0) {
        inc(retrievalSum, persona, retrievalChunks);
        inc(retrievalCount, persona);
      }
    },
    recordEmbed(status) {
      if (status === "ok") embedRequestsTotal.ok++;
      else embedRequestsTotal.err++;
    },
    recordBackendProbe(name, up) {
      backendCache[name] = up;
    },
    lastReindexSuccess(ts) {
      lastReindexTs = ts;
    },
  };

  const snapshot: MetricsSnapshot = {
    chatRequestsTotal,
    chatDurationMsSum,
    chatDurationMsCount,
    embedRequestsTotal,
    retrievalChunksReturnedSum: retrievalSum,
    retrievalChunksReturnedCount: retrievalCount,
    vaultChunksGauge: async () =>
      args.vectorStore ? await args.vectorStore.chunkCount() : 0,
    reindexLastSuccessTs: () => lastReindexTs,
    conversationsGauge: async () =>
      (await args.store.list({ limit: 999999 })).length,
    backendUp: async () => {
      // Cheap one-shot probes — populated by background prober + chat path.
      // For now we just return the most-recent cached value (the prober
      // refreshes these every 30s and the chat path opportunistically
      // marks "up" on every successful call via recordBackendProbe).
      return { ...backendCache };
    },
  };

  return { writer, snapshot };
}

/**
 * Background backend prober — pings /health on each backend every 30s
 * and updates the metrics. Returns a stop function.
 */
export function startBackendProber(args: {
  urls: { gpu: string; cpu: string; embed: string };
  writer: MetricsWriter;
  intervalMs?: number;
}): () => void {
  const interval = args.intervalMs ?? 30_000;
  let cancelled = false;

  const probe = async () => {
    for (const [name, url] of Object.entries(args.urls)) {
      let up = false;
      try {
        const ctrl = new AbortController();
        const tid = setTimeout(() => ctrl.abort(), 5_000);
        try {
          const res = await fetch(`${url}/health`, { signal: ctrl.signal });
          up = res.ok;
        } finally {
          clearTimeout(tid);
        }
      } catch { /* up stays false */ }
      args.writer.recordBackendProbe(name, up);
    }
  };

  // First probe immediately so /metrics has data on first scrape.
  probe();
  const handle = setInterval(() => {
    if (!cancelled) probe();
  }, interval);
  return () => { cancelled = true; clearInterval(handle); };
}
