/** Fan out to selected channels; adapter failures become delivery results. */

import type { Notification, DispatchResult, DeliveryResult } from "./types.js";
import type { Channel } from "../ports/channel.js";
import { CircuitBreaker, CIRCUIT_OPEN_MESSAGE } from "./circuit.js";

export interface DispatchOpts {
  /** Optional breaker. When omitted, every channel is attempted. */
  readonly breaker?: CircuitBreaker;
  /** Time source — injected so tests don't have to wait wall-clock. */
  readonly now: () => number;
}

export async function dispatch(
  notification: Notification,
  channels: readonly Channel[],
  opts: DispatchOpts,
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

  const now = opts.now;
  const breaker = opts.breaker;

  const results = await Promise.all(
    channels.map(async (ch): Promise<DeliveryResult> => {
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
