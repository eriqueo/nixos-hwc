/**
 * Transition decision engine — pure.
 *
 * Alertmanager re-POSTs every firing alert once per `repeat_interval` for as
 * long as it stays firing, and POSTs again when it resolves. Today every one of
 * those becomes a Discord message, so a week-long condition is a week of
 * identical messages and the resolve of an alert nobody ever saw is a message
 * about nothing. This module answers one question for one observation: does
 * this notification say something the previous one did not?
 *
 * Pure by construction: no clock, no database, no logger. `now` and the prior
 * durable state are parameters; the SQLite side of this lives in
 * `adapters/audit-sqlite.ts` behind the `TransitionStore` port, which calls
 * `decideTransition` inside its reservation transaction.
 *
 * SHADOW SLICE: nothing here suppresses anything. `core/pipeline.ts` records the
 * decision and its reason and then routes exactly as before. There is no
 * "enforce" mode in this slice — an unused mode would be a claim we have not
 * earned. Enforcement is a separate change, made once the recorded decisions
 * have been read against real traffic.
 *
 * Siblings ruled out for this content: `router.ts` answers "which channels"
 * (destination, not novelty); `dispatch.ts` is the fan-out over channels and
 * must stay unaware of history; `circuit.ts` is per-channel health, keyed by
 * channel id rather than by alert; `from-alertmanager.ts` is the payload
 * converter and owns no state machine. A decision keyed by alert identity and
 * fed by durable state fits none of them.
 */

import type { AlertState, Notification, Priority, TransitionTag } from "./types.js";

/** Total announce attempts allowed for one alert in one state. */
export const MAX_DELIVERY_ATTEMPTS = 3;

/** How long a P1/P2 must stay unchanged before it may remind. */
export const REMINDER_AFTER_MS = 24 * 60 * 60 * 1000;

/** Priorities allowed to remind while unchanged. 1 = critical, 2 = high. */
export const REMINDER_MAX_PRIORITY: Priority = 2;

/**
 * How long a claim may stay open before it is treated as abandoned.
 *
 * A reservation is released by `settleTransition` after dispatch. If the
 * process dies between the two, the claim would otherwise stay set forever and
 * that alert could never be announced again — a bound with no expiry is how a
 * dedup key becomes a permanent mute. Channel timeouts are 5–10 seconds, so
 * five minutes cannot overlap a live attempt; anything older is a crash, and a
 * crashed attempt is counted as a failed one.
 */
export const RESERVATION_TIMEOUT_MS = 5 * 60 * 1000;

export type TransitionOutcome = "announce" | "suppress";

export type TransitionReason =
  /** announce — first time we have ever seen this alert firing. */
  | "new-firing"
  /** announce — firing ⇄ resolved flip of an alert we had announced. */
  | "state-transition"
  /** announce — the previous attempt in this same state failed delivery. */
  | "failed-delivery-retry"
  /** announce — unchanged P1/P2 that has been quiet for 24h. */
  | "priority-reminder"
  /** suppress — resolved for something we never announced: noise. */
  | "unknown-resolved"
  /** suppress — same state, already delivered, nothing new to say. */
  | "unchanged"
  /** suppress — same state, delivery failed MAX_DELIVERY_ATTEMPTS times. */
  | "retry-exhausted"
  /** suppress — another observation of this key holds the reservation. */
  | "already-reserved";

/** Durable per-alert state. One row per transition key. */
export interface TransitionState {
  readonly key: string;
  /** The state of the last observation, not of the last announcement. */
  readonly state: AlertState;
  /** Epoch ms of the first observation ever. Never rewritten. */
  readonly firstSeenAt: number;
  /** Epoch ms of the most recent decision. */
  readonly lastDecidedAt: number;
  /** Epoch ms of the last SUCCESSFUL delivery in the current state, or null. */
  readonly announcedAt: number | null;
  /**
   * Announce attempts since the last successful delivery in the current state.
   * A successful settle resets it to 0, so it is exactly the retry counter that
   * MAX_DELIVERY_ATTEMPTS bounds. 0 together with `announcedAt === null` means
   * we chose silence for this state and never attempted anything.
   */
  readonly deliveryAttempts: number;
  /** Did the most recent attempt in the current state deliver in full? */
  readonly delivered: boolean;
  /** Is an attempt reserved and not yet settled? */
  readonly reserved: boolean;
  /** Reason recorded by the most recent decision. */
  readonly lastReason: TransitionReason;
}

export interface TransitionInput {
  readonly tag: TransitionTag;
  readonly priority: Priority;
  /** Epoch ms, injected. */
  readonly now: number;
  /** Durable state for `tag.key`, or null when this key is unknown. */
  readonly prior: TransitionState | null;
}

export interface TransitionDecision {
  readonly outcome: TransitionOutcome;
  readonly reason: TransitionReason;
  /**
   * Attempt number this decision consumes. 1 for a fresh state, N+1 for a
   * retry or a reminder, 0 when the decision announces nothing.
   */
  readonly attempt: number;
}

const suppress = (reason: TransitionReason, attempt = 0): TransitionDecision => ({
  outcome: "suppress",
  reason,
  attempt,
});

const announce = (reason: TransitionReason, attempt: number): TransitionDecision => ({
  outcome: "announce",
  reason,
  attempt,
});

/**
 * Classify one observation of one alert.
 *
 * The order of the branches is the contract:
 *  1. unknown key            → firing announces, resolved is noise
 *  2. live claim held        → another in-flight attempt owns this key
 *  3. state changed          → announce, unless we never announced the old state
 *  4. same state, never sent → we chose silence before; keep it
 *  5. same state, failed     → retry while attempts remain, then stop
 *  6. same state, delivered  → remind a stale P1/P2, otherwise say nothing
 *
 * Reasons are values, not sentences: callers route on `reason`, never on text.
 */
export function decideTransition(input: TransitionInput): TransitionDecision {
  const { tag, priority, now, prior } = input;

  // 1. Never seen this alert.
  if (prior === null) {
    return tag.state === "firing"
      ? announce("new-firing", 1)
      : suppress("unknown-resolved");
  }

  // 2. Someone reserved an attempt for this key and has not settled it.
  //    Reserving again would send the same alert twice. A claim older than
  //    RESERVATION_TIMEOUT_MS is abandoned, not live: fall through and let the
  //    branches below treat it as the failed attempt it was.
  if (prior.reserved && now - prior.lastDecidedAt < RESERVATION_TIMEOUT_MS) {
    return suppress("already-reserved");
  }

  // 3. firing ⇄ resolved. A resolve for something we never announced is noise:
  //    telling a human a problem ended when they were never told it started is
  //    strictly worse than silence.
  if (prior.state !== tag.state) {
    if (tag.state === "resolved" && prior.announcedAt === null) {
      return suppress("unknown-resolved");
    }
    return announce("state-transition", 1);
  }

  // 4. Same state we deliberately stayed silent about (never attempted).
  if (prior.deliveryAttempts === 0 && prior.announcedAt === null) {
    return suppress("unchanged");
  }

  // 5. Same state, last attempt failed. Bounded retry — see MAX_DELIVERY_ATTEMPTS.
  if (!prior.delivered) {
    return prior.deliveryAttempts < MAX_DELIVERY_ATTEMPTS
      ? announce("failed-delivery-retry", prior.deliveryAttempts + 1)
      : suppress("retry-exhausted", prior.deliveryAttempts);
  }

  // 6. Same state, already delivered. Only a stale critical earns a repeat.
  if (
    priority <= REMINDER_MAX_PRIORITY &&
    prior.announcedAt !== null &&
    now - prior.announcedAt >= REMINDER_AFTER_MS
  ) {
    return announce("priority-reminder", prior.deliveryAttempts + 1);
  }

  return suppress("unchanged", prior.deliveryAttempts);
}

/** Gate modes. `off` skips the engine entirely; `shadow` records and routes. */
export type TransitionMode = "off" | "shadow";

/**
 * The tag this notification should be evaluated under, or null.
 *
 * Null means "never gate this": either the gate is off, or the notification
 * carries no transition block — every `/notify`, CLI and MCP message, which is
 * why a human-sent P1 can never be deduplicated away by this engine.
 */
export function transitionTagOf(
  notification: Notification,
  mode: TransitionMode,
): TransitionTag | null {
  if (mode === "off") return null;
  return notification.transition ?? null;
}

/**
 * Did the whole notification reach every channel it was routed to?
 *
 * A 207 partial delivery counts as FAILED and therefore retryable: this slice
 * keeps one state per notification, not per channel, so "some channels got it"
 * has nowhere to live and pretending it succeeded would strand the channels
 * that did not. Zero attempts (no rule matched, no channels) is also not a
 * delivery.
 */
export function isFullyDelivered(result: {
  readonly attempted: number;
  readonly succeeded: number;
}): boolean {
  return result.attempted > 0 && result.succeeded === result.attempted;
}
