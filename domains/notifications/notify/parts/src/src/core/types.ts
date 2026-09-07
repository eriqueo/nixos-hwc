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

export type ExploreTarget =
  | { readonly kind: "url"; readonly label: string; readonly target: string }
  | { readonly kind: "file"; readonly label: string; readonly target: string }
  | { readonly kind: "conversation"; readonly label: string; readonly target: string }
  | { readonly kind: "command"; readonly label: string; readonly target: string }
  | { readonly kind: "record"; readonly label: string; readonly target: string };

/** Outcome-first human presentation. Optional during expand-first migration. */
export interface ExecutiveBrief {
  readonly kind: "action" | "decision" | "watch" | "handled" | "fyi";
  readonly meaning: string;
  readonly recommendation: string;
  readonly explore: ExploreTarget;
}

/**
 * Tagged transition/dedup input. Present ONLY on notifications built by the
 * Alertmanager converter (`core/from-alertmanager.ts`); the `/notify` input
 * schema does not accept it, so nothing a caller can POST is ever gated.
 *
 * `key` is deliberately independent of firing/resolved: one alert instance has
 * ONE key across its whole life, which is what makes "resolved for something we
 * never announced" and "firing → resolved" classifiable. The notification `id`
 * keeps its status suffix and is unchanged.
 */
export interface TransitionTag {
  /** Status-independent identity of the alert instance. */
  readonly key: string;
  /** Which side of the alert lifecycle this observation is. */
  readonly state: AlertState;
}

export type AlertState = "firing" | "resolved";

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
  /** Human decision surface; adapters render this before routing metadata. */
  readonly executive?: ExecutiveBrief;
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
  /** Alertmanager-only transition/dedup tag. Absent ⇒ never gated. */
  readonly transition?: TransitionTag;
}

/**
 * The body text a channel should render as its Details section, or undefined
 * when there is nothing to add.
 *
 * The executive brief is a summary, not a replacement: producers like
 * research_scout put the digest itself in `body`, and rendering only `meaning`
 * deleted it. A body that is the meaning again (whitespace aside) is the same
 * sentence twice, so it is dropped rather than repeated.
 *
 * Lives here, beside the Notification it interrogates, because it is one rule
 * that Discord and SMTP must answer identically. Not in `channel-discord.ts`
 * (SMTP would have to import an adapter), not in a new `core/detail.ts` (a
 * file for a single predicate), not in `router.ts` / `dispatch.ts` (those
 * choose destinations, not content).
 */
export function detailBody(notif: Notification): string | undefined {
  const body = notif.body.trim();
  if (body === "") return undefined;
  if (notif.executive !== undefined && body === notif.executive.meaning.trim()) return undefined;
  return body;
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
