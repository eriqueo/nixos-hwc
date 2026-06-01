/**
 * NotifyClient adapter — POST to hwc-notify's /notify endpoint.
 *
 * Single HTTP call; AbortController-based timeout; resolves with a
 * NotifyResult (never rejects). Service-to-service inside the host;
 * no auth needed on the loopback path.
 */

import type { NotifyClient, NotifyResult } from "../ports/notify.js";
import type { NotificationInput } from "../core/notify-payload.js";

export interface NotifyHttpAdapterOpts {
  readonly baseUrl: string;
  readonly timeoutMs?: number;
}

export function makeNotifyHttpClient(opts: NotifyHttpAdapterOpts): NotifyClient {
  const timeout = opts.timeoutMs ?? 5_000;
  const url = `${opts.baseUrl.replace(/\/+$/, "")}/notify`;

  return {
    async send(input: NotificationInput): Promise<NotifyResult> {
      const startedAt = Date.now();
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), timeout);
      try {
        const res = await fetch(url, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(input),
          signal: ac.signal,
        });
        const data = (await res.json().catch(() => null)) as Record<string, unknown> | null;
        const notificationId =
          data && typeof data["notificationId"] === "string" ? data["notificationId"] : undefined;
        const ok = res.status >= 200 && res.status < 300;
        return {
          ok,
          statusCode: res.status,
          ...(notificationId ? { notificationId } : {}),
          ...(ok ? {} : { message: `hwc-notify HTTP ${res.status}` }),
          durationMs: Date.now() - startedAt,
        };
      } catch (err) {
        const message = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
        return {
          ok: false,
          message,
          durationMs: Date.now() - startedAt,
        };
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
