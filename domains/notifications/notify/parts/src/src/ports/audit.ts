/**
 * AuditLog port — outbound interface for recording every dispatch.
 *
 * Core asks the audit log to `record` a full dispatch outcome
 * (notification + matched route + per-channel results). MCP / HTTP
 * shells read recent records back via `recent` for introspection.
 *
 * Implementations: SqliteAuditLog (production, node:sqlite),
 * NoopAuditLog (tests / disabled mode).
 */

import type {
  Notification,
  DeliveryResult,
  Priority,
  TransitionTag,
} from "../core/types.js";
import type {
  TransitionDecision,
  TransitionState,
} from "../core/transition.js";

export interface AuditRecord {
  readonly notification: Notification;
  readonly matchedRule: string | null;
  readonly receivedAt: string;
  readonly results: readonly DeliveryResult[];
}

export interface RecentNotification {
  readonly id: string;
  readonly title: string;
  readonly priority: Priority;
  readonly topic: string;
  readonly source: string;
  readonly tags: readonly string[];
  readonly occurredAt: string;
  readonly receivedAt: string;
  readonly matchedRule: string | null;
  readonly deliveries: readonly RecentDelivery[];
}

export interface RecentDelivery {
  readonly channelId: string;
  readonly ok: boolean;
  readonly statusCode: number | null;
  readonly message: string | null;
  readonly durationMs: number;
  readonly attemptedAt: string;
}

export interface RecentQuery {
  /** Max rows. */
  readonly limit?: number;
  /** Filter to a specific topic. */
  readonly topic?: string;
  /** Filter to a specific source. */
  readonly source?: string;
  /** Filter to only-failed (any delivery failed) or only-success. */
  readonly status?: "ok" | "failed";
}

export interface AuditLog {
  record(rec: AuditRecord): void;
  recent(query: RecentQuery): RecentNotification[];
  close(): void;
}

export interface ReserveTransitionInput {
  readonly tag: TransitionTag;
  readonly priority: Priority;
  /** Epoch ms, injected by the caller. */
  readonly now: number;
}

export interface SettleTransitionInput {
  readonly tag: TransitionTag;
  /** Epoch ms, injected by the caller. */
  readonly now: number;
  /** Did every routed channel accept the notification? (207 ⇒ false.) */
  readonly delivered: boolean;
}

/** Rows removed by one retention sweep. */
export interface CleanupCounts {
  readonly notifications: number;
  readonly deliveries: number;
  readonly transitions: number;
}

/**
 * Durable state for the transition decision engine.
 *
 * It lives on the AuditLog port, and in the same adapter and the same SQLite
 * file, on purpose: a second store would be a second writer to a single-writer
 * WAL database, and the two would disagree about the same notifications the
 * first time one of them failed a write.
 */
export interface TransitionStore {
  /**
   * Decide, and — when the decision announces — claim the attempt, in ONE
   * transaction that completes before any external effect happens. Two
   * observations of the same key cannot both hold the claim; the second is
   * classified `already-reserved`.
   *
   * Returns null when the store failed. Null is the absence of a decision, not
   * a decision to suppress — a caller that ever gates on this must treat null
   * as "route normally".
   */
  reserveTransition(input: ReserveTransitionInput): TransitionDecision | null;
  /** Release the claim and record the delivery outcome. Call after dispatch. */
  settleTransition(input: SettleTransitionInput): void;
  /** Current durable state for a key, or null. */
  getTransition(key: string): TransitionState | null;
  /** Bounded retention sweep. `now` is injected so the path is testable. */
  cleanup(now: number): CleanupCounts;
}

/** What the shells actually hold: one object, one database, one writer. */
export type AuditPort = AuditLog & TransitionStore;
