/**
 * SQLite audit log via Node 22's built-in `node:sqlite` module.
 *
 * Schema: three tables — `notifications` (one row per dispatched
 * Notification), `deliveries` (one row per channel attempt), and
 * `alert_transitions` (one row per alert instance, the durable state of
 * the transition decision engine). Each write path runs inside a single
 * transaction so a crash mid-write doesn't leave orphan delivery rows.
 *
 * Uses synchronous prepared statements — fine for our scale (handful
 * of alerts per minute peak); the in-process latency cost is dwarfed
 * by the network round-trips dispatch already waits on. The transition
 * reservation depends on that synchrony: it must complete BEFORE the
 * external effect, and it contains no `await`, so no other observation
 * can interleave between reading the prior state and claiming the attempt.
 *
 * RETENTION (Charter Law 8): AUTO-MANAGED. `cleanup(now)` drops
 * notifications + their deliveries after NOTIFICATION_RETENTION_DAYS and
 * resolved transition rows after RESOLVED_TRANSITION_RETENTION_DAYS.
 * `main.ts` runs it at startup and daily. No VACUUM anywhere: it rewrites
 * the whole file, and doing that on a request path (or from a second
 * process holding the same WAL) is how a dispatcher stops dispatching.
 *
 * Requires `node --experimental-sqlite` (set in the systemd unit's
 * ExecStart). Node prints a warning at startup that we silence with
 * `--no-warnings`.
 */

import { DatabaseSync } from "node:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type {
  AuditPort,
  AuditRecord,
  CleanupCounts,
  RecentNotification,
  RecentDelivery,
  RecentQuery,
  ReserveTransitionInput,
  SettleTransitionInput,
} from "../ports/audit.js";
import type { Logger } from "../ports/log.js";
import type { Priority } from "../core/types.js";
import {
  decideTransition,
  type TransitionDecision,
  type TransitionReason,
  type TransitionState,
} from "../core/transition.js";

/** Audit rows (notifications + their deliveries) are kept this long. */
export const NOTIFICATION_RETENTION_DAYS = 90;

/**
 * Resolved transition rows are kept this long. Shorter than the audit
 * retention on purpose: this table is working state for the decision engine,
 * and a resolved alert that has been quiet for a month has nothing left to
 * decide. Firing rows are never swept — deleting one would re-announce the
 * alert as new.
 */
export const RESOLVED_TRANSITION_RETENTION_DAYS = 30;

const DAY_MS = 24 * 60 * 60 * 1000;

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

-- Durable state of the transition decision engine. Keyed by the alert
-- instance (status-INDEPENDENT), not by notification id: one row lives
-- across a firing/resolved pair, which is what makes the pair classifiable.
-- Timestamps are epoch ms because every consumer is arithmetic, not display.
CREATE TABLE IF NOT EXISTS alert_transitions (
  key               TEXT    PRIMARY KEY,
  state             TEXT    NOT NULL,          -- firing | resolved
  first_seen_at     INTEGER NOT NULL,
  last_decided_at   INTEGER NOT NULL,
  announced_at      INTEGER,                   -- last SUCCESSFUL delivery, this state
  delivery_attempts INTEGER NOT NULL DEFAULT 0,
  delivered         INTEGER NOT NULL DEFAULT 0,-- 0 | 1
  reserved          INTEGER NOT NULL DEFAULT 0,-- 0 | 1, an attempt is in flight
  last_reason       TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_alert_transitions_state_decided ON alert_transitions(state, last_decided_at);
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

interface TransitionRow {
  key: string;
  state: string;
  first_seen_at: number;
  last_decided_at: number;
  announced_at: number | null;
  delivery_attempts: number;
  delivered: number;
  reserved: number;
  last_reason: string;
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

function rowToTransition(row: TransitionRow): TransitionState {
  return {
    key: row.key,
    state: row.state === "resolved" ? "resolved" : "firing",
    firstSeenAt: row.first_seen_at,
    lastDecidedAt: row.last_decided_at,
    announcedAt: row.announced_at,
    deliveryAttempts: row.delivery_attempts,
    delivered: row.delivered === 1,
    reserved: row.reserved === 1,
    lastReason: row.last_reason as TransitionReason,
  };
}

export function makeSqliteAuditLog(opts: SqliteAuditLogOpts): AuditPort {
  mkdirSync(dirname(opts.dbPath), { recursive: true });
  const db = new DatabaseSync(opts.dbPath);
  // Reasonable pragmas for a single-writer audit log.
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA synchronous = NORMAL;");
  db.exec("PRAGMA foreign_keys = ON;");
  db.exec(SCHEMA);

  // ON CONFLICT DO NOTHING, not INSERT OR REPLACE: the first observation of an
  // id is the true one. REPLACE deleted and re-inserted the row, which rewrote
  // received_at to the time of the LAST re-delivery (so "when did this start"
  // was unanswerable) and, with foreign_keys = ON, made the delete collide with
  // the delivery rows that pointed at it — the whole audit write then failed and
  // was swallowed by the catch below. Re-arrivals now add delivery rows only,
  // which is exactly what a retry is.
  const insertNotif = db.prepare(`
    INSERT INTO notifications
      (id, title, body, priority, topic, source, tags, context, occurred_at, received_at, matched_rule)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO NOTHING
  `);

  const insertDelivery = db.prepare(`
    INSERT INTO deliveries
      (notification_id, channel_id, ok, status_code, message, duration_ms, attempted_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  const selectTransition = db.prepare(`
    SELECT key, state, first_seen_at, last_decided_at, announced_at,
           delivery_attempts, delivered, reserved, last_reason
    FROM alert_transitions WHERE key = ?
  `);

  const insertTransition = db.prepare(`
    INSERT INTO alert_transitions
      (key, state, first_seen_at, last_decided_at, announced_at,
       delivery_attempts, delivered, reserved, last_reason)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const updateTransition = db.prepare(`
    UPDATE alert_transitions
       SET state = ?, last_decided_at = ?, announced_at = ?,
           delivery_attempts = ?, delivered = ?, reserved = ?, last_reason = ?
     WHERE key = ?
  `);

  const readTransition = (key: string): TransitionState | null => {
    const row = selectTransition.get(key) as unknown as TransitionRow | undefined;
    return row ? rowToTransition(row) : null;
  };

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

    // ── Transition state ────────────────────────────────────────────────
    getTransition(key: string): TransitionState | null {
      try {
        return readTransition(key);
      } catch (err) {
        opts.log.error("transition read failed", {
          err: err instanceof Error ? err.message : String(err),
          key,
        });
        return null;
      }
    },

    /**
     * Read the prior state, decide, and claim the attempt — one transaction,
     * no `await` inside it, completed before the caller performs the external
     * effect. A second observation of the same key that arrives while the
     * claim is open reads `reserved = 1` and is classified `already-reserved`,
     * so the alert cannot be announced twice for one claim.
     *
     * Returns null when the store itself failed. Null is NOT a decision:
     * callers must fall through to their normal behaviour, never treat it as
     * "suppress".
     */
    reserveTransition(input: ReserveTransitionInput): TransitionDecision | null {
      const { tag, priority, now } = input;
      try {
        db.exec("BEGIN IMMEDIATE");
        const prior = readTransition(tag.key);
        const decision = decideTransition({ tag, priority, now, prior });

        // A live claim belongs to the attempt that made it: a suppressed
        // duplicate writes NOTHING. Two columns make that stricter than it
        // sounds.
        //
        // `last_decided_at` is also the claim's expiry clock —
        // RESERVATION_TIMEOUT_MS is measured from it — so stamping `now` here
        // pushed the expiry forward on every duplicate. Any observation arriving
        // more often than the 5-minute timeout (Alertmanager's own retry of a
        // failed POST, or a second observation of the other side of the
        // lifecycle) then kept a CRASHED attempt claimed indefinitely, which is
        // exactly the permanent mute the timeout exists to prevent.
        //
        // `last_reason` belongs to the attempt in flight. settleTransition
        // writes the reason back when it releases the claim, so overwriting it
        // with "already-reserved" made the durable record of an announced
        // delivery read as a suppression — and reading those records against
        // real traffic is the entire point of the shadow slice.
        //
        // The decision itself is not lost: it is returned to the caller, which
        // logs it. Only the row is left alone.
        if (decision.reason === "already-reserved") {
          db.exec("COMMIT");
          return decision;
        }

        const announcing = decision.outcome === "announce";
        // Counters belong to a state. `carried` is the prior row only when this
        // observation is in the SAME state; a state change starts them over.
        const carried = prior !== null && prior.state === tag.state ? prior : null;
        const announcedAt = carried?.announcedAt ?? null;
        const attempts = announcing ? decision.attempt : carried?.deliveryAttempts ?? 0;
        const delivered = announcing ? false : carried?.delivered ?? false;

        if (prior === null) {
          insertTransition.run(
            tag.key, tag.state, now, now, announcedAt,
            attempts, delivered ? 1 : 0, announcing ? 1 : 0, decision.reason,
          );
        } else {
          updateTransition.run(
            tag.state, now, announcedAt,
            attempts, delivered ? 1 : 0, announcing ? 1 : 0, decision.reason,
            tag.key,
          );
        }
        db.exec("COMMIT");
        return decision;
      } catch (err) {
        try { db.exec("ROLLBACK"); } catch { /* ignore */ }
        opts.log.error("transition reserve failed", {
          err: err instanceof Error ? err.message : String(err),
          key: tag.key,
        });
        return null;
      }
    },

    /**
     * Release the claim and record what actually happened. A full delivery
     * resets the retry counter and stamps `announced_at`; anything less (a 207
     * partial included) leaves the counter where `reserveTransition` set it, so
     * the next observation is a bounded retry.
     */
    settleTransition(input: SettleTransitionInput): void {
      const { tag, now, delivered } = input;
      try {
        db.exec("BEGIN IMMEDIATE");
        const prior = readTransition(tag.key);
        if (prior === null || prior.state !== tag.state) {
          // Nothing to settle: the row was swept, or the alert changed state
          // mid-flight and a newer observation already owns it.
          db.exec("COMMIT");
          opts.log.warn("transition settle found no matching reservation", {
            key: tag.key,
            state: tag.state,
          });
          return;
        }
        updateTransition.run(
          prior.state,
          now,
          delivered ? now : prior.announcedAt,
          delivered ? 0 : prior.deliveryAttempts,
          delivered ? 1 : 0,
          0,
          prior.lastReason,
          tag.key,
        );
        db.exec("COMMIT");
      } catch (err) {
        try { db.exec("ROLLBACK"); } catch { /* ignore */ }
        opts.log.error("transition settle failed", {
          err: err instanceof Error ? err.message : String(err),
          key: tag.key,
        });
      }
    },

    // ── Retention (Charter Law 8: AUTO-MANAGED) ─────────────────────────
    cleanup(now: number): CleanupCounts {
      const notifCutoff = new Date(now - NOTIFICATION_RETENTION_DAYS * DAY_MS).toISOString();
      const transitionCutoff = now - RESOLVED_TRANSITION_RETENTION_DAYS * DAY_MS;
      try {
        db.exec("BEGIN IMMEDIATE");
        // Deliveries first: they reference notifications.
        const deliveries = db
          .prepare(
            `DELETE FROM deliveries
              WHERE notification_id IN (SELECT id FROM notifications WHERE received_at < ?)`,
          )
          .run(notifCutoff);
        const notifications = db
          .prepare("DELETE FROM notifications WHERE received_at < ?")
          .run(notifCutoff);
        // Only resolved rows. A firing row is live state — dropping it would
        // make the next repeat look like a brand-new alert.
        const transitions = db
          .prepare(
            "DELETE FROM alert_transitions WHERE state = 'resolved' AND last_decided_at < ?",
          )
          .run(transitionCutoff);
        db.exec("COMMIT");
        const counts: CleanupCounts = {
          notifications: Number(notifications.changes),
          deliveries: Number(deliveries.changes),
          transitions: Number(transitions.changes),
        };
        opts.log.info("audit retention sweep", { ...counts, notifCutoff });
        return counts;
      } catch (err) {
        try { db.exec("ROLLBACK"); } catch { /* ignore */ }
        opts.log.error("audit retention sweep failed", {
          err: err instanceof Error ? err.message : String(err),
        });
        return { notifications: 0, deliveries: 0, transitions: 0 };
      }
    },

    close(): void {
      db.close();
    },
  };
}
