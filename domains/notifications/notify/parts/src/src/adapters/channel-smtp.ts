/**
 * SMTP channel adapter.
 *
 * Sends a Notification as plain-text email via an SMTP relay (typically
 * Proton Bridge on loopback). Auth credentials are read from a file
 * path at startup — never logged.
 *
 * `send` resolves with a DeliveryResult (never rejects). Connection /
 * greeting / socket timeouts are capped so a stuck SMTP server doesn't
 * hang the dispatcher.
 */

import { readFileSync } from "node:fs";
import nodemailer, { type Transporter } from "nodemailer";
import type { Channel } from "../ports/channel.js";
import type { Notification, DeliveryResult, Priority } from "../core/types.js";

const PRIORITY_LABEL: Record<Priority, string> = {
  1: "P1 CRITICAL",
  2: "P2 HIGH",
  3: "P3 WARN",
  4: "P4 INFO",
  5: "P5 LOW",
};

export interface SmtpChannelOpts {
  readonly id: string;
  readonly name: string;
  readonly params: {
    readonly host: string;
    readonly port: number;
    /** Send STARTTLS after EHLO. For Proton Bridge on loopback: false. */
    readonly requireTls: boolean;
    readonly login: string;
    /** Absolute path to a file containing the SMTP password. */
    readonly passwordFile: string;
    readonly from: string;
    readonly to: string;
    readonly timeoutMs: number;
  };
}

/** Render a Notification as a plain-text email body. */
function renderBody(notif: Notification): string {
  const lines: string[] = [];
  lines.push(notif.body || "(no body)");
  lines.push("");
  lines.push("—");
  lines.push(`Priority:   ${PRIORITY_LABEL[notif.priority]}`);
  lines.push(`Topic:      ${notif.topic}`);
  lines.push(`Source:     ${notif.source}`);
  lines.push(`Occurred:   ${notif.occurredAt}`);
  if (notif.tags.length > 0) {
    lines.push(`Tags:       ${notif.tags.join(", ")}`);
  }
  if (Object.keys(notif.context).length > 0) {
    lines.push("");
    lines.push("Context:");
    for (const [k, v] of Object.entries(notif.context)) {
      const rendered = typeof v === "string" ? v : JSON.stringify(v);
      lines.push(`  ${k}: ${rendered}`);
    }
  }
  lines.push("");
  lines.push(`Notification id: ${notif.id}`);
  return lines.join("\n");
}

export function makeSmtpChannel(opts: SmtpChannelOpts): Channel {
  // Read the password ONCE at construction. If the secret rotates, the
  // service needs a restart — same contract as Discord webhook URLs.
  const password = readFileSync(opts.params.passwordFile, "utf8").replace(/\s+$/u, "");

  // Build the transporter ONCE; nodemailer pools the underlying TCP
  // socket per send within `pool: true`. For our low-volume use the
  // simpler one-shot per-send is fine.
  const transporter: Transporter = nodemailer.createTransport({
    host: opts.params.host,
    port: opts.params.port,
    secure: false,
    requireTLS: opts.params.requireTls,
    auth: { user: opts.params.login, pass: password },
    // Bridge ships a self-signed cert; we're on loopback so MITM is
    // moot. When requireTls = false, this object is effectively unused.
    tls: { rejectUnauthorized: false },
    connectionTimeout: Math.min(opts.params.timeoutMs, 5000),
    greetingTimeout: Math.min(opts.params.timeoutMs, 5000),
    socketTimeout: opts.params.timeoutMs,
  });

  return {
    id: opts.id,
    name: opts.name,
    adapter: "smtp",

    async send(notif: Notification): Promise<DeliveryResult> {
      const startedAt = Date.now();
      try {
        const info = await transporter.sendMail({
          from: opts.params.from,
          to: opts.params.to,
          subject: `[${PRIORITY_LABEL[notif.priority]}] ${notif.title}`,
          text: renderBody(notif),
        });

        return {
          channelId: opts.id,
          ok: true,
          statusCode: 250,
          message: info.messageId,
          durationMs: Date.now() - startedAt,
        };
      } catch (err) {
        const message = err instanceof Error
          ? `${err.name}: ${err.message}`
          : String(err);
        return {
          channelId: opts.id,
          ok: false,
          message,
          durationMs: Date.now() - startedAt,
        };
      }
    },
  };
}
