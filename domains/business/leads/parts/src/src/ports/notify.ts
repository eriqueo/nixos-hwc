/**
 * NotifyClient port — outbound interface for telling hwc-notify
 * about a new lead.
 */

import type { NotificationInput } from "../core/notify-payload.js";

export interface NotifyResult {
  readonly ok: boolean;
  readonly statusCode?: number;
  readonly notificationId?: string;
  readonly message?: string;
  readonly durationMs: number;
}

export interface NotifyClient {
  send(input: NotificationInput): Promise<NotifyResult>;
}
