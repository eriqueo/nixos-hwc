/**
 * Discord webhook adapter.
 *
 * Builds an embed from a Notification and POSTs it to a Discord
 * channel webhook. Color is mapped from priority; routing metadata is demoted
 * to the footer. The webhook URL is a secret — read at startup from
 * an agenix-mounted file path, never logged.
 *
 * `send` resolves with a DeliveryResult (never rejects); the HTTP shell
 * uses the result to build the response status. Circuit-breaker logic
 * is core's job in a later chunk; for now a single attempt with a
 * 5-second timeout.
 */

import type { Channel } from "../ports/channel.js";
import type { Notification, DeliveryResult, Priority } from "../core/types.js";

const COLOR_BY_PRIORITY: Record<Priority, number> = {
  1: 0xe74c3c, // red — critical
  2: 0xe67e22, // orange — high
  3: 0xf1c40f, // yellow — warning
  4: 0x3498db, // blue — info (default)
  5: 0x2ecc71, // green — low / success
};

interface DiscordEmbed {
  title: string;
  description: string;
  color: number;
  timestamp: string;
  fields: ReadonlyArray<{ name: string; value: string; inline?: boolean }>;
  footer: { text: string };
  url?: string;
}

interface DiscordWebhookPayload {
  username: string;
  embeds: readonly DiscordEmbed[];
}

export interface DiscordChannelOpts {
  readonly id: string;
  readonly name: string;
  /** Username shown in the Discord channel. */
  readonly username?: string;
  /** Discord webhook URL — secret; loaded from agenix at startup. */
  readonly webhookUrl: string;
  /** Network timeout per delivery attempt. */
  readonly timeoutMs?: number;
}

/** Discord caps embed.description at 4096 and field.value at 1024. */
function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1) + "…";
}

function renderExplore(notif: Notification): string | undefined {
  const explore = notif.executive?.explore;
  if (!explore) return undefined;
  if (explore.kind === "url") return `[${explore.label}](${explore.target})`;
  if (explore.kind === "command") return `${explore.label}: \`${explore.target}\``;
  return `${explore.label}: ${explore.target}`;
}

/** Pure production rendering decision, exported for contract tests. */
export function renderDiscordEmbed(notif: Notification): DiscordEmbed {
  const executive = notif.executive;
  const fields: Array<{ name: string; value: string; inline?: boolean }> = [];
  if (executive) {
    fields.push({ name: "Recommendation", value: truncate(executive.recommendation, 1024) });
    const explore = renderExplore(notif);
    if (explore) fields.push({ name: "Explore", value: truncate(explore, 1024) });
  }
  const metadata = [notif.source, notif.topic, ...notif.tags].filter(Boolean).join(" · ");
  const url = executive?.explore.kind === "url" ? executive.explore.target : undefined;
  return {
    title: truncate(notif.title, 256),
    description: truncate(executive?.meaning ?? notif.body, 4096),
    color: COLOR_BY_PRIORITY[notif.priority],
    timestamp: notif.occurredAt,
    fields,
    footer: { text: truncate(metadata, 2048) },
    ...(url !== undefined ? { url } : {}),
  };
}

export function makeDiscordChannel(opts: DiscordChannelOpts): Channel {
  const username = opts.username ?? "HWC Alerts";
  const timeoutMs = opts.timeoutMs ?? 5000;

  return {
    id: opts.id,
    name: opts.name,
    adapter: "discord",

    async send(notif: Notification): Promise<DeliveryResult> {
      const startedAt = Date.now();

      const payload: DiscordWebhookPayload = {
        username,
        embeds: [renderDiscordEmbed(notif)],
      };

      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), timeoutMs);

      try {
        const res = await fetch(opts.webhookUrl, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload),
          signal: ac.signal,
        });

        // Discord webhooks return 204 No Content on success.
        const ok = res.status >= 200 && res.status < 300;
        const message = ok
          ? undefined
          : `discord webhook returned HTTP ${res.status}`;

        return {
          channelId: opts.id,
          ok,
          statusCode: res.status,
          ...(message !== undefined ? { message } : {}),
          durationMs: Date.now() - startedAt,
        };
      } catch (err) {
        // fetch throws on network errors, abort, DNS failure, etc.
        const message = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
        return {
          channelId: opts.id,
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
