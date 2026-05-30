import { Database } from "@db/sqlite";
import { v1 as uuidv1 } from "@std/uuid";
import type { ConversationStore } from "../ports/store.ts";
import type { ChatRole, ConversationMeta, Turn } from "../core/types.ts";
import type { ClockPort } from "../ports/clock.ts";
import { PersonaDaemonError } from "../core/errors.ts";

const SCHEMA_VERSION = 1;

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
];

export function openDatabase(path: string): Database {
  const db = new Database(path);

  // WAL + busy timeout — readers and the single writer don't block each other.
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA synchronous = NORMAL;");
  db.exec("PRAGMA busy_timeout = 5000;");
  db.exec("PRAGMA foreign_keys = ON;");

  // Bootstrap the schema_version table itself before reading it.
  db.exec(
    "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)",
  );
  db.exec("INSERT OR IGNORE INTO schema_version (version) VALUES (0)");

  const current = db.prepare("SELECT version FROM schema_version LIMIT 1")
    .get<{ version: number }>()?.version ?? 0;

  for (let v = current; v < SCHEMA_VERSION; v++) {
    db.exec(MIGRATIONS[v]);
    db.prepare("UPDATE schema_version SET version = ?").run(v + 1);
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
