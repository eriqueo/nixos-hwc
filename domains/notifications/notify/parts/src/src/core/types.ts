/**
 * Core domain types.
 *
 * Hexagonal architecture: these types are the canonical shape of the
 * domain. Shells (HTTP, CLI, MCP) parse external input into Notification
 * via Zod schemas at the boundary; adapters (Discord, SMTP, …) accept a
 * Notification and produce a DeliveryResult. Core never imports from
 * shells or adapters.
 */

/** Priority levels — same numeric scheme as Alertmanager / iOS push. */
export type Priority = 1 | 2 | 3 | 4 | 5;

/**
 * A Notification is the atomic unit the dispatcher routes and delivers.
 * Every inbound message — HTTP, CLI, Alertmanager webhook — is parsed
 * into this shape before core touches it.
 */
export interface Notification {
  /** Stable, idempotent key. Phase 1.2: caller-supplied or auto-generated UUID. */
  readonly id: string;
  /** Short headline (Discord embed title, email subject). */
  readonly title: string;
  /** Body text. Markdown-ish; channel adapters render appropriately. */
  readonly body: string;
  /** 1 = critical (red) … 5 = info (green). */
  readonly priority: Priority;
  /** Routing topic — "monitoring", "leads", "backup", etc. Free-form slug. */
  readonly topic: string;
  /** Origin of this notification — "alertmanager", "calculator", "manual", … */
  readonly source: string;
  /** Free-form tags. Channel adapters may surface these (Discord field, email header). */
  readonly tags: readonly string[];
  /** Arbitrary structured context (alert labels, JT job ID, …). Adapter-discretion to render. */
  readonly context: Readonly<Record<string, unknown>>;
  /** ISO-8601 timestamp of when the notification was *generated*, not received. */
  readonly occurredAt: string;
}

/** Result of a single channel delivery attempt. */
export interface DeliveryResult {
  readonly channelId: string;
  readonly ok: boolean;
  /** HTTP status / SMTP response code / etc. when meaningful. */
  readonly statusCode?: number;
  /** Adapter-specific message — error reason on failure, opaque on success. */
  readonly message?: string;
  /** Elapsed wall-clock time for the attempt. */
  readonly durationMs: number;
}

/** Aggregate result of dispatching one notification across N channels. */
export interface DispatchResult {
  readonly notificationId: string;
  readonly attempted: number;
  readonly succeeded: number;
  readonly failed: number;
  readonly results: readonly DeliveryResult[];
}
