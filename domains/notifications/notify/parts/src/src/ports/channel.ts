/**
 * Channel port — outbound delivery interface.
 *
 * One implementation per delivery target (Discord, SMTP, Gotify, …).
 * Core asks the registered Channels to `send(notification)` and
 * aggregates results. Channels are constructed at startup with
 * adapter-specific config (webhook URLs, SMTP creds) and reused.
 */

import type { Notification, DeliveryResult } from "../core/types.js";

export interface Channel {
  /** Stable channel ID — used in routing config and audit log. */
  readonly id: string;
  /** Short human-readable name for logs / UI. */
  readonly name: string;
  /** Adapter type — "discord", "smtp", "log-only", … */
  readonly adapter: string;
  /** Attempt delivery. MUST resolve (never reject); errors land in DeliveryResult.ok = false. */
  send(notification: Notification): Promise<DeliveryResult>;
}
