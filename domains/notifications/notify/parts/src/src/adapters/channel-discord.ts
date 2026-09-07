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
import type { Notification, DeliveryResult, ExploreTarget, Priority } from "../core/types.js";
import { detailBody } from "../core/types.js";

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

/**
 * Discord's documented per-embed caps. `TOTAL` is the sum of title +
 * description + field names + field values + footer across the embed; exceeding
 * it is a 400, so the Details budget below is computed against it rather than
 * assumed.
 */
const LIMIT = {
  TITLE: 256,
  DESCRIPTION: 4096,
  FIELD_VALUE: 1024,
  FOOTER: 2048,
  TOTAL: 6000,
} as const;

/**
 * The executive path caps the description at the schema's own `meaning` bound
 * instead of the 4096 embed bound. Same output for anything that came through
 * `parseNotificationInput` (meaning is already ≤ 1000), and it makes the
 * Details budget provable: title 256 + meaning 1000 + recommendation 500 +
 * explore 1024 + field names 28 + footer 2048 = 4856 worst case, leaving 1144
 * — more than the 1024 field allowance — for Details.
 */
const MEANING_LIMIT = 1000;

const DETAIL_FIELD_NAME = "Details";

function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max - 1) + "…";
}

/**
 * Fit the body detail into `budget` characters, saying so when it does not fit.
 *
 * A digest that quietly stops mid-sentence reads like the digest ended. The
 * notice names the full length and repeats the exact explore location, so the
 * reader can tell detail was cut and where the whole of it lives — the same
 * target the Explore field and the embed URL already carry.
 */
function fitDetail(detail: string, budget: number, explore: ExploreTarget): string {
  if (detail.length <= budget) return detail;
  const notice = `\n… [truncated — full ${detail.length} characters at: ${explore.target}]`;
  const kept = budget - notice.length;
  // Degenerate only if the explore target alone exceeds the field: keep the
  // fact of truncation over any prefix of the detail.
  if (kept < 1) return truncate(`[truncated — full detail at: ${explore.target}]`, budget);
  return detail.slice(0, kept) + notice;
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
  const metadata = [notif.source, notif.topic, ...notif.tags].filter(Boolean).join(" · ");
  const title = truncate(notif.title, LIMIT.TITLE);
  const footer = truncate(metadata, LIMIT.FOOTER);
  // Legacy (no executive): the body is the whole message and stays the
  // description, byte-for-byte as before.
  const description = executive
    ? truncate(executive.meaning, MEANING_LIMIT)
    : truncate(notif.body, LIMIT.DESCRIPTION);

  if (executive) {
    fields.push({ name: "Recommendation", value: truncate(executive.recommendation, LIMIT.FIELD_VALUE) });
    const explore = renderExplore(notif);
    if (explore) fields.push({ name: "Explore", value: truncate(explore, LIMIT.FIELD_VALUE) });

    // Decision first, then the long form. A field rather than more
    // description keeps "Details" labelled and keeps Explore above it.
    const detail = detailBody(notif);
    if (detail !== undefined) {
      const used =
        title.length +
        description.length +
        footer.length +
        DETAIL_FIELD_NAME.length +
        fields.reduce((n, f) => n + f.name.length + f.value.length, 0);
      const budget = Math.max(0, Math.min(LIMIT.FIELD_VALUE, LIMIT.TOTAL - used));
      // budget is ≥ 1024 for any schema-parsed notification (see MEANING_LIMIT);
      // the guard is for hand-built Notifications that ignore those bounds.
      if (budget > 0) {
        fields.push({ name: DETAIL_FIELD_NAME, value: fitDetail(detail, budget, executive.explore) });
      }
    }
  }

  const url = executive?.explore.kind === "url" ? executive.explore.target : undefined;
  return {
    title,
    description,
    color: COLOR_BY_PRIORITY[notif.priority],
    timestamp: notif.occurredAt,
    fields,
    footer: { text: footer },
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
