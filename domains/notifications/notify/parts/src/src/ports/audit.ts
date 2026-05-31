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
} from "../core/types.js";

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
