import { Database } from "@db/sqlite";
import { v1 as uuidv1 } from "@std/uuid";
import type { ConversationStore, VectorStore } from "../ports/store.ts";
import type { ChatRole, ConversationMeta, Turn } from "../core/types.ts";
import type { ClockPort } from "../ports/clock.ts";
import type { Chunk } from "../core/chunking.ts";
import type { ScoredChunk } from "../core/retrieval.ts";
import { cosine } from "../core/retrieval.ts";
import { PersonaDaemonError } from "../core/errors.ts";

const SCHEMA_VERSION = 2;

const MIGRATIONS = [
  // v0 → v1 — Commit 2 baseline
  `
    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT PRIMARY KEY,
      persona_id TEXT NOT NULL,
      title TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      summary TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_conv_persona
      ON conversations(persona_id, updated_at DESC);

    CREATE TABLE IF NOT EXISTS turns (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL
        REFERENCES conversations(id) ON DELETE CASCADE,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      token_count INTEGER,
      created_at INTEGER NOT NULL,
      dropped INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_turns_conv
      ON turns(conversation_id, created_at ASC);
  `,

  // v1 → v2 — Commit 3: vault chunks for RAG
  `
    CREATE TABLE IF NOT EXISTS chunks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_path TEXT NOT NULL,
      section_title TEXT NOT NULL,
      parent_section TEXT NOT NULL,
      kind TEXT NOT NULL,            -- 'text' | 'code' | 'frontmatter' | 'moc'
      char_start INTEGER NOT NULL,
      char_end INTEGER NOT NULL,
      body TEXT NOT NULL,
      embedding BLOB NOT NULL,       -- Float32Array bytes; dim asserted by adapter
      mtime INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(note_path);
  `,
];

export function openDatabase(path: string): Database {
  const db = new Database(path);

  // WAL + busy timeout — readers and the single writer don't block each other.
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA synchronous = NORMAL;");
  db.exec("PRAGMA busy_timeout = 5000;");
  db.exec("PRAGMA foreign_keys = ON;");

  // Bootstrap: schema_version is a single-row table. Idempotent on cold and
  // hot starts — INSERT OR IGNORE on a PK-only schema lets stale rows pile
  // up, so we read MAX(version) and rewrite as one row per migration step.
  db.exec(
    "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)",
  );
  const rowCount = db.prepare("SELECT COUNT(*) AS n FROM schema_version")
    .get<{ n: number }>()?.n ?? 0;
  if (rowCount === 0) {
    db.exec("INSERT INTO schema_version (version) VALUES (0)");
  }

  const current = db.prepare("SELECT MAX(version) AS v FROM schema_version")
    .get<{ v: number | null }>()?.v ?? 0;

  for (let v = current; v < SCHEMA_VERSION; v++) {
    db.exec(MIGRATIONS[v]);
    db.exec("DELETE FROM schema_version");
    db.prepare("INSERT INTO schema_version (version) VALUES (?)").run(v + 1);
  }

  return db;
}

interface CreateOpts {
  db: Database;
  clock: ClockPort;
}

export function createConversationStoreSqlite(
  { db, clock }: CreateOpts,
): ConversationStore {

  // Retry one SQLITE_BUSY before giving up — combined with PRAGMA busy_timeout
  // this is belt+suspenders for the rare contention window between reindex
  // (Commit 3) and chat write.
  function withBusyRetry<T>(fn: () => T): T {
    try {
      return fn();
    } catch (e) {
      if (e instanceof Error && /SQLITE_BUSY|database is locked/i.test(e.message)) {
        return fn();
      }
      throw e;
    }
  }

  function mapTurn(row: TurnRow): Turn {
    return {
      id: row.id,
      conversationId: row.conversation_id,
      role: row.role as ChatRole,
      content: row.content,
      tokenCount: row.token_count,
      createdAt: row.created_at,
    };
  }

  function mapMeta(row: ConvRow & { turn_count: number }): ConversationMeta {
    return {
      id: row.id,
      personaId: row.persona_id,
      title: row.title,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      turnCount: row.turn_count,
    };
  }

  return {
    create(personaId, title) {
      return Promise.resolve(withBusyRetry(() => {
        const id = uuidv1.generate() as string;
        const now = clock.now();
        db.prepare(
          `INSERT INTO conversations (id, persona_id, title, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)`,
        ).run(id, personaId, title ?? null, now, now);
        return id;
      }));
    },

    appendTurn({ conversationId, role, content, tokenCount }) {
      return Promise.resolve(withBusyRetry(() => {
        const exists = db.prepare(
          "SELECT 1 FROM conversations WHERE id = ?",
        ).get(conversationId);
        if (!exists) {
          throw new PersonaDaemonError(
            "CONVERSATION_NOT_FOUND",
            `conversation ${conversationId} does not exist`,
          );
        }
        const id = uuidv1.generate() as string;
        const now = clock.now();
        db.prepare(
          `INSERT INTO turns (id, conversation_id, role, content, token_count, created_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
        ).run(id, conversationId, role, content, tokenCount, now);
        db.prepare(
          "UPDATE conversations SET updated_at = ? WHERE id = ?",
        ).run(now, conversationId);
        return {
          id,
          conversationId,
          role,
          content,
          tokenCount,
          createdAt: now,
        } satisfies Turn;
      }));
    },

    getRecent(conversationId, n) {
      const rows = db.prepare(
        `SELECT id, conversation_id, role, content, token_count, created_at
         FROM turns
         WHERE conversation_id = ? AND dropped = 0
         ORDER BY created_at DESC
         LIMIT ?`,
      ).all<TurnRow>(conversationId, n);
      return Promise.resolve(rows.reverse().map(mapTurn));
    },

    getSummary(conversationId) {
      const row = db.prepare(
        "SELECT summary FROM conversations WHERE id = ?",
      ).get<{ summary: string | null }>(conversationId);
      return Promise.resolve(row?.summary ?? null);
    },

    setSummary(conversationId, summary, droppedTurnIds) {
      return Promise.resolve(withBusyRetry(() => {
        const tx = db.transaction((ids: string[]) => {
          db.prepare(
            "UPDATE conversations SET summary = ?, updated_at = ? WHERE id = ?",
          ).run(summary, clock.now(), conversationId);
          const stmt = db.prepare(
            "UPDATE turns SET dropped = 1 WHERE id = ?",
          );
          for (const id of ids) stmt.run(id);
        });
        tx(droppedTurnIds);
      }));
    },

    exists(conversationId) {
      const row = db.prepare(
        "SELECT 1 FROM conversations WHERE id = ?",
      ).get(conversationId);
      return Promise.resolve(!!row);
    },

    getMeta(conversationId) {
      const row = db.prepare(
        `SELECT c.id, c.persona_id, c.title, c.created_at, c.updated_at,
                (SELECT COUNT(*) FROM turns t WHERE t.conversation_id = c.id) AS turn_count
         FROM conversations c
         WHERE c.id = ?`,
      ).get<ConvRow & { turn_count: number }>(conversationId);
      return Promise.resolve(row ? mapMeta(row) : null);
    },

    list({ personaId, limit }) {
      const sql = personaId
        ? `SELECT c.id, c.persona_id, c.title, c.created_at, c.updated_at,
                  (SELECT COUNT(*) FROM turns t WHERE t.conversation_id = c.id) AS turn_count
           FROM conversations c WHERE persona_id = ?
           ORDER BY updated_at DESC LIMIT ?`
        : `SELECT c.id, c.persona_id, c.title, c.created_at, c.updated_at,
                  (SELECT COUNT(*) FROM turns t WHERE t.conversation_id = c.id) AS turn_count
           FROM conversations c
           ORDER BY updated_at DESC LIMIT ?`;
      const stmt = db.prepare(sql);
      const rows = personaId
        ? stmt.all<ConvRow & { turn_count: number }>(personaId, limit)
        : stmt.all<ConvRow & { turn_count: number }>(limit);
      return Promise.resolve(rows.map(mapMeta));
    },
  };
}

interface ConvRow {
  id: string;
  persona_id: string;
  title: string | null;
  created_at: number;
  updated_at: number;
}

interface TurnRow {
  id: string;
  conversation_id: string;
  role: string;
  content: string;
  token_count: number | null;
  created_at: number;
}

// ─────────────────────────────────────────────────────────────────────────
// VectorStore — chunks table + in-memory Float32Array[] mirror
// ─────────────────────────────────────────────────────────────────────────

interface ChunkRow {
  id: number;
  note_path: string;
  section_title: string;
  parent_section: string;
  kind: string;
  char_start: number;
  char_end: number;
  body: string;
  embedding: Uint8Array;
  mtime: number;
}

interface MirrorEntry {
  chunk: Chunk;
  vec: Float32Array;
}

function bytesToFloat32(bytes: Uint8Array): Float32Array {
  // Copy to avoid alignment issues with the BLOB's underlying buffer.
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return new Float32Array(copy.buffer);
}

function float32ToBytes(vec: Float32Array): Uint8Array {
  return new Uint8Array(vec.buffer, vec.byteOffset, vec.byteLength);
}

function rowToChunk(row: ChunkRow): Chunk {
  return {
    notePath: row.note_path,
    sectionTitle: row.section_title,
    parentSection: row.parent_section,
    kind: row.kind as Chunk["kind"],
    charStart: row.char_start,
    charEnd: row.char_end,
    body: row.body,
    mtime: row.mtime,
  };
}

export function createVectorStoreSqlite(args: {
  db: Database;
  expectedDim: number | null;       // null = don't enforce at startup
}): VectorStore & { entries(): IterableIterator<MirrorEntry> } {
  const { db, expectedDim } = args;
  const mirror: MirrorEntry[] = [];

  function withBusyRetry<T>(fn: () => T): T {
    try {
      return fn();
    } catch (e) {
      if (e instanceof Error && /SQLITE_BUSY|database is locked/i.test(e.message)) {
        return fn();
      }
      throw e;
    }
  }

  function rebuildMirrorSync(): void {
    mirror.length = 0;
    const rows = db.prepare(
      `SELECT id, note_path, section_title, parent_section, kind,
              char_start, char_end, body, embedding, mtime
       FROM chunks`,
    ).all<ChunkRow>();
    for (const row of rows) {
      const vec = bytesToFloat32(row.embedding);
      if (expectedDim !== null && vec.length !== expectedDim) {
        throw new PersonaDaemonError(
          "CONFIG_INVALID",
          `chunk ${row.id} has ${vec.length}-dim embedding but expectedDim=${expectedDim}`,
          { notePath: row.note_path },
        );
      }
      mirror.push({ chunk: rowToChunk(row), vec });
    }
  }

  // Initial load.
  rebuildMirrorSync();

  return {
    upsertNoteChunks(notePath, chunks, embeddings, mtime) {
      if (chunks.length !== embeddings.length) {
        throw new PersonaDaemonError(
          "CONFIG_INVALID",
          "upsertNoteChunks: chunks and embeddings length mismatch",
          { notePath, chunks: chunks.length, embeddings: embeddings.length },
        );
      }
      return Promise.resolve(withBusyRetry(() => {
        const tx = db.transaction((_: null) => {
          db.prepare("DELETE FROM chunks WHERE note_path = ?").run(notePath);
          const insert = db.prepare(
            `INSERT INTO chunks
               (note_path, section_title, parent_section, kind,
                char_start, char_end, body, embedding, mtime)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          );
          for (let i = 0; i < chunks.length; i++) {
            const c = chunks[i];
            insert.run(
              c.notePath, c.sectionTitle, c.parentSection, c.kind,
              c.charStart, c.charEnd, c.body,
              float32ToBytes(embeddings[i]), mtime,
            );
          }
        });
        tx(null);

        // Update in-memory mirror to reflect this note's new chunks.
        for (let i = mirror.length - 1; i >= 0; i--) {
          if (mirror[i].chunk.notePath === notePath) mirror.splice(i, 1);
        }
        for (let i = 0; i < chunks.length; i++) {
          mirror.push({ chunk: chunks[i], vec: embeddings[i] });
        }
      }));
    },

    deleteNote(notePath) {
      return Promise.resolve(withBusyRetry(() => {
        db.prepare("DELETE FROM chunks WHERE note_path = ?").run(notePath);
        for (let i = mirror.length - 1; i >= 0; i--) {
          if (mirror[i].chunk.notePath === notePath) mirror.splice(i, 1);
        }
      }));
    },

    topK(queryVec, k) {
      const scored: ScoredChunk[] = [];
      for (const { chunk, vec } of mirror) {
        let s = cosine(queryVec, vec);
        if (chunk.kind === "frontmatter") s *= 0.5;
        scored.push({ ...chunk, score: s });
      }
      scored.sort((a, b) => b.score - a.score);
      return Promise.resolve(scored.slice(0, k));
    },

    allMtimes() {
      const rows = db.prepare(
        "SELECT note_path, MIN(mtime) AS mtime FROM chunks GROUP BY note_path",
      ).all<{ note_path: string; mtime: number }>();
      const m = new Map<string, number>();
      for (const r of rows) m.set(r.note_path, r.mtime);
      return Promise.resolve(m);
    },

    chunkCount() {
      const row = db.prepare("SELECT COUNT(*) AS n FROM chunks").get<{ n: number }>();
      return Promise.resolve(row?.n ?? 0);
    },

    reloadMirror() {
      rebuildMirrorSync();
      return Promise.resolve();
    },

    entries() {
      return mirror[Symbol.iterator]();
    },
  };
}
