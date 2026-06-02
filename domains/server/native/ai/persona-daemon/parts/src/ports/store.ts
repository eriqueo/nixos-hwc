import type { ChatRole, ConversationMeta, Turn } from "../core/types.ts";
import type { Chunk } from "../core/chunking.ts";
import type { ScoredChunk } from "../core/retrieval.ts";

export interface ConversationStore {
  create(personaId: string, title?: string): Promise<string>;

  appendTurn(args: {
    conversationId: string;
    role: ChatRole;
    content: string;
    tokenCount: number | null;
  }): Promise<Turn>;

  getRecent(conversationId: string, n: number): Promise<Turn[]>;
  getSummary(conversationId: string): Promise<string | null>;
  setSummary(
    conversationId: string,
    summary: string,
    droppedTurnIds: string[],
  ): Promise<void>;
  exists(conversationId: string): Promise<boolean>;
  getMeta(conversationId: string): Promise<ConversationMeta | null>;
  list(opts: { personaId?: string; limit: number }): Promise<ConversationMeta[]>;
}

export interface VectorStore {
  /** Replace all chunks for a note (delete + insert in a transaction).
   *  `contentHash` is persisted alongside so the indexer can skip the note
   *  on the next scan unless its bytes change. */
  upsertNoteChunks(
    notePath: string,
    chunks: Chunk[],
    embeddings: Float32Array[],
    mtime: number,
    contentHash: string,
  ): Promise<void>;

  /** Delete every chunk for the given note path. */
  deleteNote(notePath: string): Promise<void>;

  /** Top-K cosine over all live chunks (with frontmatter de-weighting). */
  topK(queryVec: Float32Array, k: number): Promise<ScoredChunk[]>;

  /** path → content-hash map; the indexer compares sha256(body) against this
   *  to decide what changed. Content-addressed so Syncthing mtime churn is a
   *  no-op. */
  allNoteHashes(): Promise<Map<string, string>>;

  /** Total chunk count — useful for /metrics and quick smoke tests. */
  chunkCount(): Promise<number>;

  /** Force a full re-load of the in-memory vector mirror from SQLite. */
  reloadMirror(): Promise<void>;
}
