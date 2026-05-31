/**
 * SQLite audit log via Node 22's built-in `node:sqlite` module.
 *
 * Schema: two tables — `notifications` (one row per dispatched
 * Notification) and `deliveries` (one row per channel attempt).
 * Both write paths run inside a single transaction so a crash
 * mid-write doesn't leave orphan delivery rows.
 *
 * Uses synchronous prepared statements — fine for our scale (handful
 * of alerts per minute peak); the in-process latency cost is dwarfed
 * by the network round-trips dispatch already waits on.
 *
 * Requires `node --experimental-sqlite` (set in the systemd unit's
 * ExecStart). Node prints a warning at startup that we silence with
 * `--no-warnings`.
 */

import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type {
  AuditLog,
  AuditRecord,
  RecentNotification,
  RecentDelivery,
  RecentQuery,
} from "../ports/audit.js";
import type { Logger } from "../ports/log.js";
import type { Priority } from "../core/types.js";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS notifications (
  id            TEXT    PRIMARY KEY,
  title         TEXT    NOT NULL,
  body          TEXT    NOT NULL,
  priority      INTEGER NOT NULL,
  topic         TEXT    NOT NULL,
  source        TEXT    NOT NULL,
  tags          TEXT    NOT NULL,  -- JSON array
  context       TEXT    NOT NULL,  -- JSON object
  occurred_at   TEXT    NOT NULL,
  received_at   TEXT    NOT NULL,
  matched_rule  TEXT
);

CREATE INDEX IF NOT EXISTS idx_notifications_received_at ON notifications(received_at);
CREATE INDEX IF NOT EXISTS idx_notifications_topic       ON notifications(topic);
CREATE INDEX IF NOT EXISTS idx_notifications_source      ON notifications(source);

CREATE TABLE IF NOT EXISTS deliveries (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id TEXT    NOT NULL,
  channel_id      TEXT    NOT NULL,
  ok              INTEGER NOT NULL,  -- 0 | 1
  status_code     INTEGER,
  message         TEXT,
  duration_ms     INTEGER NOT NULL,
  attempted_at    TEXT    NOT NULL,
  FOREIGN KEY (notification_id) REFERENCES notifications(id)
);

CREATE INDEX IF NOT EXISTS idx_deliveries_notification_id        ON deliveries(notification_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_channel_attempted      ON deliveries(channel_id, attempted_at);
CREATE INDEX IF NOT EXISTS idx_deliveries_ok                     ON deliveries(ok);
`;

export interface SqliteAuditLogOpts {
  readonly dbPath: string;
  readonly log: Logger;
}

interface NotifRow {
  id: string;
  title: string;
  body: string;
  priority: number;
  topic: string;
  source: string;
  tags: string;
  context: string;
  occurred_at: string;
  received_at: string;
  matched_rule: string | null;
}

interface DeliveryRow {
  notification_id: string;
  channel_id: string;
  ok: number;
  status_code: number | null;
  message: string | null;
  duration_ms: number;
  attempted_at: string;
}

function isPriority(n: number): n is Priority {
  return n === 1 || n === 2 || n === 3 || n === 4 || n === 5;
}

function rowToRecent(notif: NotifRow, deliveries: DeliveryRow[]): RecentNotification {
  const tags: readonly string[] = (() => {
    try {
      const parsed = JSON.parse(notif.tags);
      return Array.isArray(parsed) ? parsed.filter((t): t is string => typeof t === "string") : [];
    } catch {
      return [];
    }
  })();

  const recentDeliveries: RecentDelivery[] = deliveries.map((d) => ({
    channelId: d.channel_id,
    ok: d.ok === 1,
    statusCode: d.status_code,
    message: d.message,
    durationMs: d.duration_ms,
    attemptedAt: d.attempted_at,
  }));

  return {
    id: notif.id,
    title: notif.title,
    priority: isPriority(notif.priority) ? notif.priority : 3,
    topic: notif.topic,
    source: notif.source,
    tags,
    occurredAt: notif.occurred_at,
    receivedAt: notif.received_at,
    matchedRule: notif.matched_rule,
    deliveries: recentDeliveries,
  };
}

export function makeSqliteAuditLog(opts: SqliteAuditLogOpts): AuditLog {
  mkdirSync(dirname(opts.dbPath), { recursive: true });
  const db = new DatabaseSync(opts.dbPath);
  // Reasonable pragmas for a single-writer audit log.
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA synchronous = NORMAL;");
  db.exec("PRAGMA foreign_keys = ON;");
  db.exec(SCHEMA);

  const insertNotif = db.prepare(`
    INSERT OR REPLACE INTO notifications
      (id, title, body, priority, topic, source, tags, context, occurred_at, received_at, matched_rule)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const insertDelivery = db.prepare(`
    INSERT INTO deliveries
      (notification_id, channel_id, ok, status_code, message, duration_ms, attempted_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  // node:sqlite's prepare doesn't have a `transaction` helper; wrap manually.
  return {
    record(rec: AuditRecord): void {
      try {
        db.exec("BEGIN");
        insertNotif.run(
          rec.notification.id,
          rec.notification.title,
          rec.notification.body,
          rec.notification.priority,
          rec.notification.topic,
          rec.notification.source,
          JSON.stringify(rec.notification.tags),
          JSON.stringify(rec.notification.context),
          rec.notification.occurredAt,
          rec.receivedAt,
          rec.matchedRule,
        );
        for (const d of rec.results) {
          insertDelivery.run(
            rec.notification.id,
            d.channelId,
            d.ok ? 1 : 0,
            d.statusCode ?? null,
            d.message ?? null,
            d.durationMs,
            rec.receivedAt,
          );
        }
        db.exec("COMMIT");
      } catch (err) {
        try { db.exec("ROLLBACK"); } catch { /* ignore */ }
        opts.log.error("audit write failed", {
          err: err instanceof Error ? err.message : String(err),
          notificationId: rec.notification.id,
        });
      }
    },

    recent(query: RecentQuery): RecentNotification[] {
      const limit = Math.min(query.limit ?? 50, 500);
      const filters: string[] = [];
      const params: Array<string | number> = [];
      if (query.topic) {
        filters.push("topic = ?");
        params.push(query.topic);
      }
      if (query.source) {
        filters.push("source = ?");
        params.push(query.source);
      }
      if (query.status === "failed") {
        // notification has at least one failed delivery
        filters.push(
          "id IN (SELECT notification_id FROM deliveries WHERE ok = 0)",
        );
      } else if (query.status === "ok") {
        // notification has NO failed deliveries AND at least one attempt
        filters.push(
          "id NOT IN (SELECT notification_id FROM deliveries WHERE ok = 0) " +
          "AND id IN (SELECT notification_id FROM deliveries)",
        );
      }
      const whereClause = filters.length > 0 ? ` WHERE ${filters.join(" AND ")}` : "";

      const notifs = db
        .prepare(
          `SELECT id, title, body, priority, topic, source, tags, context,
                  occurred_at, received_at, matched_rule
           FROM notifications
           ${whereClause}
           ORDER BY received_at DESC
           LIMIT ?`,
        )
        .all(...params, limit) as unknown as NotifRow[];

      if (notifs.length === 0) return [];

      const placeholders = notifs.map(() => "?").join(", ");
      const deliveries = db
        .prepare(
          `SELECT notification_id, channel_id, ok, status_code, message,
                  duration_ms, attempted_at
           FROM deliveries
           WHERE notification_id IN (${placeholders})
           ORDER BY attempted_at ASC`,
        )
        .all(...notifs.map((n) => n.id)) as unknown as DeliveryRow[];

      const byNotif = new Map<string, DeliveryRow[]>();
      for (const d of deliveries) {
        const arr = byNotif.get(d.notification_id) ?? [];
        arr.push(d);
        byNotif.set(d.notification_id, arr);
      }

      return notifs.map((n) => rowToRecent(n, byNotif.get(n.id) ?? []));
    },

    close(): void {
      db.close();
    },
  };
}
