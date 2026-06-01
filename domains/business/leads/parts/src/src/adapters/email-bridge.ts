/**
 * CustomerEmailClient adapter — nodemailer over Proton Bridge.
 *
 * Same wiring hwc-notify's smtp-eric channel uses (loopback 127.0.0.1:1025,
 * STARTTLS required even on the local socket, AUTH PLAIN with the
 * send-address as the user). Bridge ships a self-signed cert; the
 * transport sets rejectUnauthorized:false because we're on loopback
 * and MITM is moot.
 *
 * The password is loaded once at construction; rotation requires a
 * service restart (handled by restartTriggers on the .age file).
 */

import nodemailer, { type Transporter } from "nodemailer";
import type { CustomerEmailClient, CustomerEmailResult } from "../ports/customer-email.js";
import type { RenderedEmail } from "../core/customer-email.js";
import type { SmtpConfig } from "../config.js";
import type { Logger } from "../ports/log.js";

export interface BridgeEmailAdapterOpts {
  readonly smtp: SmtpConfig;
  readonly log: Logger;
  readonly timeoutMs?: number;
}

export function makeBridgeEmailClient(opts: BridgeEmailAdapterOpts): CustomerEmailClient {
  const timeout = opts.timeoutMs ?? 10_000;

  const transporter: Transporter = nodemailer.createTransport({
    host: opts.smtp.host,
    port: opts.smtp.port,
    secure: false,
    requireTLS: opts.smtp.requireTls,
    auth: { user: opts.smtp.login, pass: opts.smtp.password },
    tls: { rejectUnauthorized: false },
    connectionTimeout: Math.min(timeout, 5_000),
    greetingTimeout: Math.min(timeout, 5_000),
    socketTimeout: timeout,
  });

  opts.log.info("customer-email transporter built", {
    host: opts.smtp.host,
    port: opts.smtp.port,
    login: opts.smtp.login,
    from: opts.smtp.from,
    requireTls: opts.smtp.requireTls,
  });

  return {
    async send(email: RenderedEmail): Promise<CustomerEmailResult> {
      const startedAt = Date.now();
      try {
        const info = await transporter.sendMail({
          from: opts.smtp.from,
          to: email.to,
          subject: email.subject,
          text: email.body,
        });
        return {
          ok: true,
          messageId: info.messageId,
          durationMs: Date.now() - startedAt,
        };
      } catch (err) {
        const message = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
        return {
          ok: false,
          message,
          durationMs: Date.now() - startedAt,
        };
      }
    },
  };
}
