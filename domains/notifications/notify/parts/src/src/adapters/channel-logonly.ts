/**
 * Log-only channel — for dev / disabled-channel slots / testing.
 *
 * Implements the Channel port but doesn't talk to any external service;
 * just emits a structured log line and reports success. Useful when a
 * routing config points at a real channel ID that hasn't been wired up
 * yet, or during local development without secrets.
 */

import type { Channel } from "../ports/channel.js";
import type { Notification, DeliveryResult } from "../core/types.js";
import type { Logger } from "../ports/log.js";

export interface LogOnlyChannelOpts {
  readonly id: string;
  readonly name: string;
  readonly log: Logger;
}

export function makeLogOnlyChannel(opts: LogOnlyChannelOpts): Channel {
  return {
    id: opts.id,
    name: opts.name,
    adapter: "log-only",

    async send(notif: Notification): Promise<DeliveryResult> {
      const startedAt = Date.now();
      opts.log.info("log-only channel delivery (dry-run)", {
        channelId: opts.id,
        notification: {
          id: notif.id,
          title: notif.title,
          priority: notif.priority,
          topic: notif.topic,
          source: notif.source,
        },
      });
      return {
        channelId: opts.id,
        ok: true,
        durationMs: Date.now() - startedAt,
      };
    },
  };
}
