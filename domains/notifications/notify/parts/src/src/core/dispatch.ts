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

import type { Notification, DispatchResult } from "./types.js";
import type { Channel } from "../ports/channel.js";

export async function dispatch(
  notification: Notification,
  channels: readonly Channel[],
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

  // Promise.all is safe because Channel.send is documented never to
  // reject; we double-belt it with a defensive .catch just in case
  // an adapter breaks the contract.
  const results = await Promise.all(
    channels.map(async (ch) => {
      try {
        return await ch.send(notification);
      } catch (err) {
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
