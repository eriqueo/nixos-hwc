/**
 * The one path a Notification takes: reserve → route → dispatch → audit → settle.
 *
 * WHY THIS IS A MODULE AND NOT TWO COPIES IN THE HTTP SHELL
 *
 * `POST /notify` and `POST /webhook/alertmanager` ran byte-identical versions of
 * these six steps, differing only in how they shaped the response. Two copies of
 * an ordering contract is two places for it to drift, and the ordering IS the
 * contract: the reservation must be claimed BEFORE the external effect (a
 * Discord POST cannot be un-sent), and released only AFTER the result and the
 * audit row exist. A copy that gets one of those wrong sends an alert twice.
 *
 * It also makes the gate un-removable by accident. The handlers no longer have a
 * `dispatch` of their own to fall back to — deleting the gate from a handler now
 * deletes the handler's only source of a result, which does not compile.
 * `__tests__/pipeline-wiring.test.ts` covers the remaining hole: deleting the two
 * gate calls from THIS file.
 *
 * Siblings ruled out for this content: `dispatch.ts` is the per-channel fan-out
 * and must stay unaware of history — putting the gate there would evaluate it
 * once per CHANNEL, which is the exact mistake the design forbids (a P1 that
 * fans out to Discord + SMTP is one decision, not two). `router.ts` is a pure
 * "which channels" function. `transition.ts` is pure by construction — no clock,
 * no store — and this orchestrates both.
 *
 * SHADOW SLICE: the decision never changes what is routed. `open` records it and
 * returns the tag only when the engine WOULD have announced; everything is
 * dispatched either way. There is no branch here that can drop a notification.
 */

import { dispatch } from "./dispatch.js";
import { route } from "./router.js";
import { isFullyDelivered, transitionTagOf, type TransitionMode } from "./transition.js";
import type { CircuitBreaker } from "./circuit.js";
import type { DispatchResult, Notification, TransitionTag } from "./types.js";
import type { AuditPort } from "../ports/audit.js";
import type { Channel } from "../ports/channel.js";
import type { Logger } from "../ports/log.js";
import type { RoutingRule } from "../schemas/runtime-config.js";

export interface PipelineDeps {
  readonly audit: AuditPort;
  /** Built channels, keyed by id — the same map the router's ids index. */
  readonly channels: ReadonlyMap<string, Channel>;
  readonly routes: readonly RoutingRule[];
  readonly defaultChannels: readonly string[];
  readonly transitionMode: TransitionMode;
  readonly breaker: CircuitBreaker;
  /**
   * Epoch-ms clock, bound ONCE at the composition root (`main.ts` passes
   * `Date.now`). Nothing below this line reads the wall clock directly, which is
   * what lets the wiring test assert on timestamps instead of tolerating them.
   */
  readonly now: () => number;
}

export interface PipelineOutcome {
  readonly result: DispatchResult;
  readonly matchedRule: string | null;
}

/** A claim this notification holds and must release. Null ⇒ nothing to release. */
interface PendingTransition {
  readonly tag: TransitionTag;
}

/**
 * Claim an attempt for this notification, if it carries a transition tag.
 *
 * Runs ONCE per notification, before routing — not once per channel — so the
 * deliberate P1 Discord+SMTP fan-out and the research Discord+email fan-out stay
 * one decision each.
 */
function openTransition(
  deps: PipelineDeps,
  notification: Notification,
  log: Logger,
): PendingTransition | null {
  const tag = transitionTagOf(notification, deps.transitionMode);
  // No tag ⇒ not an Alertmanager notification (or the engine is off). Nothing a
  // caller can POST carries a tag, so /notify traffic is never gated.
  if (tag === null) return null;

  const decision = deps.audit.reserveTransition({
    tag,
    priority: notification.priority,
    now: deps.now(),
  });
  // Null is the absence of a decision (the store failed), never a suppression.
  if (decision === null) return null;

  log.info("transition decision (shadow — routing unchanged)", {
    notificationId: notification.id,
    transitionKey: tag.key,
    transitionState: tag.state,
    outcome: decision.outcome,
    reason: decision.reason,
    attempt: decision.attempt,
    mode: deps.transitionMode,
  });

  // Settle only what the engine would actually have sent. Shadow mode still
  // delivers everything, but recording a delivery the engine classified as
  // suppressible would refresh `announced_at` on every repeat and the 24h P1/P2
  // reminder could never come due — the recorded decisions have to describe what
  // enforcement WOULD do, or measuring them proves nothing.
  return decision.outcome === "announce" ? { tag } : null;
}

/** Release the claim with the outcome the external effect actually produced. */
function closeTransition(
  deps: PipelineDeps,
  pending: PendingTransition | null,
  result: DispatchResult,
): void {
  if (pending === null) return;
  deps.audit.settleTransition({
    tag: pending.tag,
    now: deps.now(),
    delivered: isFullyDelivered(result),
  });
}

/**
 * Run one notification end to end. Never throws: `dispatch` absorbs channel
 * errors into DeliveryResults and the audit adapter swallows its own write
 * failures, so the caller always gets a result to answer with.
 *
 * If something between the reservation and the settle DOES throw, the claim is
 * deliberately left open rather than released in a `finally`: there is no
 * delivery outcome to record at that point, and RESERVATION_TIMEOUT_MS is the
 * designed recovery for a claim whose owner died.
 */
export async function dispatchNotification(
  deps: PipelineDeps,
  notification: Notification,
  log: Logger,
): Promise<PipelineOutcome> {
  const pending = openTransition(deps, notification, log);

  const decision = route(notification, deps.routes, deps.defaultChannels);
  const targets = decision.channelIds
    .map((id) => deps.channels.get(id))
    .filter((c): c is Channel => c !== undefined);

  log.info("dispatching notification", {
    notificationId: notification.id,
    topic: notification.topic,
    priority: notification.priority,
    source: notification.source,
    matchedRule: decision.matchedRule,
    channelIds: targets.map((c) => c.id),
  });

  const receivedAt = new Date(deps.now()).toISOString();
  const result = await dispatch(notification, targets, { breaker: deps.breaker });

  log.info("dispatch complete", {
    notificationId: notification.id,
    attempted: result.attempted,
    succeeded: result.succeeded,
    failed: result.failed,
  });

  deps.audit.record({
    notification,
    matchedRule: decision.matchedRule,
    receivedAt,
    results: result.results,
  });
  closeTransition(deps, pending, result);

  return { result, matchedRule: decision.matchedRule };
}
