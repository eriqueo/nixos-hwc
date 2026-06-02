import type { NoteSource } from "../ports/notes.ts";
import type { EmbedPort } from "../ports/llm.ts";
import type { VectorStore } from "../ports/store.ts";
import type { LogPort } from "../ports/log.ts";
import { chunkNote } from "./chunking.ts";

export interface IndexerDeps {
  notes: NoteSource;
  embed: EmbedPort;
  vectorStore: VectorStore;
  log: LogPort;
  /** Embedder is more efficient called in batches than one-by-one. */
  embedBatchSize?: number;
}

export interface IndexerStats {
  scanned: number;
  unchanged: number;
  reindexed: number;
  deleted: number;
  chunksWritten: number;
  durationMs: number;
}

export function createIndexer(deps: IndexerDeps) {
  // Each chunk can be up to ~1024 tokens; we keep batches small enough that
  // total tokens stay under llama-server's --ubatch-size (8192). 4 chunks ≈
  // 4096 tokens worst case; in practice most chunks are short.
  const batchSize = deps.embedBatchSize ?? 4;
  let inFlight = false;
  let lastSuccessTs: number | null = null;

  async function sha256Hex(text: string): Promise<string> {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(text),
    );
    const bytes = new Uint8Array(digest);
    let hex = "";
    for (const b of bytes) hex += b.toString(16).padStart(2, "0");
    return hex;
  }

  // Embed + persist one note's chunks. The caller has already read the body and
  // confirmed (via content hash) that it changed; `contentHash` is stored so the
  // next scan can skip an unchanged note without re-embedding it.
  async function indexBody(
    path: string,
    body: string,
    mtime: number,
    contentHash: string,
  ): Promise<number> {
    const chunks = chunkNote({ notePath: path, body, mtime });
    if (chunks.length === 0) {
      // Empty / non-text note — purge any prior chunks.
      await deps.vectorStore.deleteNote(path);
      return 0;
    }
    const embeddings: Float32Array[] = [];
    for (let i = 0; i < chunks.length; i += batchSize) {
      const batch = chunks.slice(i, i + batchSize).map((c) => c.body);
      const vecs = await deps.embed.embed(batch);
      embeddings.push(...vecs);
    }
    await deps.vectorStore.upsertNoteChunks(path, chunks, embeddings, mtime, contentHash);
    return chunks.length;
  }

  async function run(opts?: { full?: boolean; notePath?: string }): Promise<IndexerStats> {
    if (inFlight) {
      deps.log.warn("reindex.skipped", { reason: "already in flight" });
      return {
        scanned: 0, unchanged: 0, reindexed: 0,
        deleted: 0, chunksWritten: 0, durationMs: 0,
      };
    }
    inFlight = true;
    const t0 = performance.now();

    const stats: IndexerStats = {
      scanned: 0, unchanged: 0, reindexed: 0,
      deleted: 0, chunksWritten: 0, durationMs: 0,
    };

    try {
      const existing = await deps.vectorStore.allNoteHashes();

      // Single-note reindex (admin CLI with --note). Hash-gated like the full
      // scan: a trigger on a note whose bytes are unchanged does no embedding.
      if (opts?.notePath) {
        const path = opts.notePath;
        try {
          stats.scanned = 1;
          const body = await deps.notes.read(path);
          const hash = await sha256Hex(body);
          if (!opts.full && existing.get(path) === hash) {
            stats.unchanged = 1;
          } else {
            stats.chunksWritten = await indexBody(path, body, Date.now(), hash);
            stats.reindexed = 1;
          }
        } catch (e) {
          await deps.vectorStore.deleteNote(path);
          stats.deleted = 1;
          deps.log.warn("reindex.note_missing", { notePath: path, err: String(e) });
        }
        stats.durationMs = Math.round(performance.now() - t0);
        lastSuccessTs = Date.now();
        deps.log.info("reindex.note.complete", { ...stats });
        return stats;
      }

      // Full / incremental scan — re-embed only notes whose CONTENT changed.
      // mtime is deliberately ignored for the decision (the vault is Syncthing-
      // replicated; mtimes change on every sync without the bytes changing). It
      // is still passed through to chunk storage as informational metadata.
      const seen = new Set<string>();
      for await (const { path, mtime } of deps.notes.list()) {
        stats.scanned++;
        seen.add(path);
        let body: string;
        try {
          body = await deps.notes.read(path);
        } catch (e) {
          deps.log.error("reindex.note_failed", {
            notePath: path,
            err: e instanceof Error ? e.message : String(e),
          });
          continue;
        }
        const hash = await sha256Hex(body);
        if (!opts?.full && existing.get(path) === hash) {
          stats.unchanged++;
          continue;
        }
        try {
          const written = await indexBody(path, body, mtime, hash);
          stats.reindexed++;
          stats.chunksWritten += written;
        } catch (e) {
          deps.log.error("reindex.note_failed", {
            notePath: path,
            err: e instanceof Error ? e.message : String(e),
          });
        }
      }

      // Delete chunks for notes that disappeared from the vault.
      for (const path of existing.keys()) {
        if (!seen.has(path)) {
          await deps.vectorStore.deleteNote(path);
          stats.deleted++;
        }
      }

      stats.durationMs = Math.round(performance.now() - t0);
      lastSuccessTs = Date.now();
      deps.log.info("reindex.complete", { ...stats });
      return stats;
    } finally {
      inFlight = false;
    }
  }

  return {
    run,
    isRunning: () => inFlight,
    lastSuccess: () => lastSuccessTs,
  };
}
