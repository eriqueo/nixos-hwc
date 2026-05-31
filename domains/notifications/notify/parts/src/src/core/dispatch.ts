/**
 * Dispatch — pure orchestration of a Notification across channels.
 *
 * Phase 1.2: send to every registered channel concurrently and
 * aggregate results. No routing logic yet (that arrives in 1.3 as
 * a data-driven match-list); for now the caller decides which
 * channels apply.
 *
 * Errors from individual channels are absorbed into per-channel
 * DeliveryResults — `dispatch` never throws. The HTTP shell uses
 * the DispatchResult to compute a response code (200 if all ok,
 * 207 if mixed, 502 if all failed).
 */

import type { Notification, DispatchResult, DeliveryResult } from "./types.js";
import type { Channel } from "../ports/channel.js";
import { CircuitBreaker, CIRCUIT_OPEN_MESSAGE } from "./circuit.js";

export interface DispatchOpts {
  /** Optional breaker. When omitted, every channel is attempted. */
  readonly breaker?: CircuitBreaker;
  /** Time source — injected so tests don't have to wait wall-clock. */
  readonly now?: () => number;
}

export async function dispatch(
  notification: Notification,
  channels: readonly Channel[],
  opts: DispatchOpts = {},
): Promise<DispatchResult> {
  if (channels.length === 0) {
    return {
      notificationId: notification.id,
      attempted: 0,
      succeeded: 0,
      failed: 0,
      results: [],
    };
  }

  const now = opts.now ?? Date.now;
  const breaker = opts.breaker;

  const results = await Promise.all(
    channels.map(async (ch): Promise<DeliveryResult> => {
      // Circuit breaker check — skip the channel without calling send().
      if (breaker && !breaker.shouldAttempt(ch.id, now())) {
        return {
          channelId: ch.id,
          ok: false,
          message: CIRCUIT_OPEN_MESSAGE,
          durationMs: 0,
        };
      }

      try {
        const result = await ch.send(notification);
        if (breaker) {
          if (result.ok) breaker.recordSuccess(ch.id, now());
          else breaker.recordFailure(ch.id, now());
        }
        return result;
      } catch (err) {
        if (breaker) breaker.recordFailure(ch.id, now());
        const message = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
        return {
          channelId: ch.id,
          ok: false,
          message: `adapter contract violation (threw): ${message}`,
          durationMs: 0,
        };
      }
    }),
  );

  const succeeded = results.filter((r) => r.ok).length;
  return {
    notificationId: notification.id,
    attempted: channels.length,
    succeeded,
    failed: channels.length - succeeded,
    results,
  };
}
