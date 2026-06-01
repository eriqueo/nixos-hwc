/**
 * hwc-leads — entry point.
 *
 * Phase 2.2 wiring:
 *   GET  /health     — liveness + downstream wiring check
 *   POST /leads      — HMAC-verified, schema-validated. Returns 202 +
 *                      Lead id. Downstream calls (JT, Postgres, notify,
 *                      email) land in Phase 2.3+.
 */

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { loadConfig } from "./config.js";
import { makeStderrLogger } from "./adapters/log-stderr.js";
import { safeParseLeadInput, buildLead } from "./schemas/lead.js";
import { verifyHmac } from "./core/hmac.js";
import { makePostgresLeadStore } from "./adapters/store-postgres.js";
import { makeJtJobtreadAdapter } from "./adapters/jt-jobtread.js";
import { makeNotifyHttpClient } from "./adapters/notify-http.js";
import { makeBridgeEmailClient } from "./adapters/email-bridge.js";
import { buildNotificationInput } from "./core/notify-payload.js";
import { renderCustomerEmail } from "./core/customer-email.js";
import type { LeadStore } from "./ports/store.js";
import type { JtClient } from "./ports/jt.js";
import type { NotifyClient } from "./ports/notify.js";
import type { CustomerEmailClient } from "./ports/customer-email.js";

const MAX_BODY_BYTES = 64 * 1024;

function readRawBody(req: IncomingMessage): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let total = 0;
    req.on("data", (chunk: Buffer) => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        reject(new Error(`request body exceeded ${MAX_BODY_BYTES} bytes`));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function writeJson(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload).toString(),
  });
  res.end(payload);
}

function main(): void {
  const config = loadConfig();
  const log = makeStderrLogger({
    minLevel: config.logLevel,
    serviceName: config.serviceName,
  });

  log.info("hwc-leads starting", {
    bindAddr: config.bindAddr,
    port: config.port,
    logLevel: config.logLevel,
    notifyServiceUrl: config.notifyServiceUrl,
    hmacWired: config.hmacSecret !== undefined,
    jtGrantWired: config.jtGrantKey !== undefined,
    postgresDsn: config.postgresDsn,
  });

  const store: LeadStore = makePostgresLeadStore({
    dsn: config.postgresDsn,
    log: log.child({ component: "postgres" }),
  });

  const jt: JtClient | undefined = config.jtGrantKey
    ? makeJtJobtreadAdapter({
        grantKey: config.jtGrantKey,
        mappings: config.jtMappings,
        log: log.child({ component: "jt" }),
      })
    : undefined;

  if (!jt) {
    log.warn("JT graph creation disabled (jtGrantKey unwired) — leads will save with empty jt:{}");
  }

  const notifyClient: NotifyClient = makeNotifyHttpClient({
    baseUrl: config.notifyServiceUrl,
  });

  const emailClient: CustomerEmailClient | undefined = config.smtp
    ? makeBridgeEmailClient({
        smtp: config.smtp,
        log: log.child({ component: "customer-email" }),
      })
    : undefined;

  if (!emailClient) {
    log.warn("customer email disabled (smtp config not wired)");
  }

  const startedAt = new Date();

  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
    const url = req.url ?? "/";
    const method = req.method ?? "GET";
    const reqLog = log.child({ method, url });

    // ── GET /health ────────────────────────────────────────────────────
    if (method === "GET" && url === "/health") {
      writeJson(res, 200, {
        status: "ok",
        service: config.serviceName,
        version: config.version,
        uptimeSeconds: Math.round((Date.now() - startedAt.getTime()) / 1000),
        downstream: {
          notifyServiceUrl: config.notifyServiceUrl,
          hmacWired: config.hmacSecret !== undefined,
          jtGrantWired: config.jtGrantKey !== undefined,
        },
      });
      return;
    }

    // ── POST /leads ────────────────────────────────────────────────────
    if (method === "POST" && url === "/leads") {
      void (async () => {
        let raw: Buffer;
        try {
          raw = await readRawBody(req);
        } catch (err) {
          reqLog.warn("body read error", {
            err: err instanceof Error ? err.message : String(err),
          });
          writeJson(res, 400, {
            code: "VALIDATION_ERROR",
            message: err instanceof Error ? err.message : "invalid request body",
          });
          return;
        }

        // ── 1. HMAC verification (raw bytes) ──
        if (config.hmacSecret !== undefined) {
          const sigHeader = req.headers["x-hwc-signature"];
          const sig = Array.isArray(sigHeader) ? sigHeader[0] : sigHeader;
          const verification = verifyHmac(config.hmacSecret, raw, sig);
          if (!verification.ok) {
            reqLog.warn("hmac verification failed", { reason: verification.reason });
            writeJson(res, 401, {
              code: "HMAC_MISMATCH",
              message: `signature ${verification.reason}`,
            });
            return;
          }
        } else {
          // hmacSecret unset means HMAC explicitly disabled in config —
          // a dev-only mode. Log a warning EVERY request so it's loud.
          reqLog.warn("HMAC verification skipped (hmacSecret unset — DEV ONLY)");
        }

        // ── 2. JSON parse ──
        let parsed: unknown;
        try {
          parsed = JSON.parse(raw.toString("utf8"));
        } catch (err) {
          reqLog.warn("json parse error", {
            err: err instanceof Error ? err.message : String(err),
          });
          writeJson(res, 400, {
            code: "VALIDATION_ERROR",
            message: "invalid JSON body",
          });
          return;
        }

        // ── 3. Schema validation ──
        const result = safeParseLeadInput(parsed);
        if (!result.ok) {
          reqLog.warn("lead schema validation failed", { issues: result.issues });
          writeJson(res, 400, {
            code: "VALIDATION_ERROR",
            message: "Lead input schema validation failed",
            issues: result.issues,
          });
          return;
        }

        // ── 4. Build canonical Lead ──
        const lead = buildLead(result.value);

        reqLog.info("lead accepted", {
          leadId: lead.id,
          source: lead.payload.source,
          contactEmail: lead.payload.contact.email,
        });

        // ── 5. Persist ──
        try {
          await store.save(lead);
          reqLog.info("lead persisted", { leadId: lead.id });
        } catch (err) {
          const reason = err instanceof Error ? err.message : String(err);
          reqLog.error("postgres save failed", { leadId: lead.id, err: reason });
          writeJson(res, 500, {
            code: "POSTGRES_ERROR",
            message: "lead validated but persistence failed; retry safe",
            leadId: lead.id,
          });
          return;
        }

        // ── 6. JT graph creation (Phase 2.4) ──
        // Idempotent on the row's existing JT IDs; saves whatever was
        // created back to the DB even on partial failure so a future
        // replay can pick up where this attempt left off.
        let jtIds: { accountId?: string; locationId?: string; contactId?: string; jobId?: string } = {};
        let jtError: string | undefined;
        let jtRetryable: boolean | undefined;
        let nextStatus: "complete" | "pending_jt" | "validated" = "validated";

        if (jt) {
          const result = await jt.createGraph(lead, {});
          jtIds = {
            ...(result.ids.accountId  ? { accountId:  result.ids.accountId  } : {}),
            ...(result.ids.locationId ? { locationId: result.ids.locationId } : {}),
            ...(result.ids.contactId  ? { contactId:  result.ids.contactId  } : {}),
            ...(result.ids.jobId      ? { jobId:      result.ids.jobId      } : {}),
          };
          nextStatus = result.complete ? "complete" : "pending_jt";
          if (!result.complete) {
            jtError = result.error;
            jtRetryable = result.retryable;
            reqLog.warn("jt graph partial", {
              leadId: lead.id,
              failedAt: result.failedAt,
              retryable: result.retryable,
              ids: jtIds,
            });
          }

          // Persist whatever happened.
          try {
            await store.updateJtIds(lead.id, jtIds, nextStatus);
          } catch (err) {
            reqLog.error("jt id update failed", {
              leadId: lead.id,
              err: err instanceof Error ? err.message : String(err),
            });
          }
        }

        // ── 7. hwc-notify ping ──
        // Pass the lead with its newly minted JT IDs so the
        // notification body can include the JT job deep-link.
        const leadWithJt = { ...lead, jt: jtIds };
        let notifyOk = false;
        let notifyMsg: string | undefined;
        try {
          const notifInput = buildNotificationInput(leadWithJt, undefined);
          const r = await notifyClient.send(notifInput);
          notifyOk = r.ok;
          notifyMsg = r.ok ? undefined : r.message;
          if (r.ok) {
            try { await store.markNotified(lead.id); } catch { /* logged separately */ }
            reqLog.info("hwc-notify ping ok", { leadId: lead.id, notificationId: r.notificationId });
          } else {
            reqLog.warn("hwc-notify ping failed", { leadId: lead.id, err: r.message });
          }
        } catch (err) {
          notifyOk = false;
          notifyMsg = err instanceof Error ? err.message : String(err);
          reqLog.warn("hwc-notify ping threw", { leadId: lead.id, err: notifyMsg });
        }

        // ── 8. Customer email ──
        let emailOk = false;
        let emailMsg: string | undefined;
        if (emailClient) {
          try {
            const rendered = renderCustomerEmail(leadWithJt);
            const r = await emailClient.send(rendered);
            emailOk = r.ok;
            emailMsg = r.ok ? undefined : r.message;
            if (r.ok) {
              try { await store.markEmailSent(lead.id); } catch { /* logged separately */ }
              reqLog.info("customer email sent", { leadId: lead.id, messageId: r.messageId });
            } else {
              reqLog.warn("customer email failed", { leadId: lead.id, err: r.message });
            }
          } catch (err) {
            emailOk = false;
            emailMsg = err instanceof Error ? err.message : String(err);
            reqLog.warn("customer email threw", { leadId: lead.id, err: emailMsg });
          }
        }

        writeJson(res, 202, {
          leadId: lead.id,
          source: lead.payload.source,
          status: nextStatus,
          receivedAt: lead.receivedAt,
          jt: jtIds,
          ...(jtError ? { jtError, jtRetryable } : {}),
          notify: { ok: notifyOk, ...(notifyMsg ? { message: notifyMsg } : {}) },
          email: emailClient
            ? { ok: emailOk, ...(emailMsg ? { message: emailMsg } : {}) }
            : { ok: false, message: "disabled" },
          message:
            "lead processed; partial-failure recovery via Phase 2.7 replay endpoint.",
        });
      })();
      return;
    }

    // ── GET /leads/recent ──────────────────────────────────────────────
    if (method === "GET" && url.startsWith("/leads/recent")) {
      void (async () => {
        try {
          const u = new URL(url, `http://${config.bindAddr}`);
          const limit = Math.min(500, Math.max(1, parseInt(u.searchParams.get("limit") ?? "50", 10) || 50));
          const sourceParam = u.searchParams.get("source");
          const statusParam = u.searchParams.get("status");
          const validSources = ["contact", "calculator", "appointment"] as const;
          const validStatuses = ["received", "validated", "pending_jt", "complete", "failed"] as const;
          const source = validSources.find((s) => s === sourceParam);
          const status = validStatuses.find((s) => s === statusParam);
          const rows = await store.recent({
            limit,
            ...(source ? { source } : {}),
            ...(status ? { status } : {}),
          });
          writeJson(res, 200, { count: rows.length, rows });
        } catch (err) {
          reqLog.error("recent query failed", { err: err instanceof Error ? err.message : String(err) });
          writeJson(res, 500, { code: "POSTGRES_ERROR", message: "recent query failed" });
        }
      })();
      return;
    }

    writeJson(res, 404, {
      code: "NOT_FOUND",
      message: `no route: ${method} ${url}`,
    });
  });

  server.on("error", (err) => {
    log.error("http server error", { err: String(err) });
    process.exitCode = 1;
    server.close();
  });

  server.listen(config.port, config.bindAddr, () => {
    log.info("hwc-leads listening", {
      bindAddr: config.bindAddr,
      port: config.port,
    });
  });

  const shutdown = (signal: string): void => {
    log.info("shutdown signal received", { signal });
    server.close(async (err) => {
      if (err) log.error("server close error", { err: String(err) });
      try { await store.close(); } catch { /* ignore */ }
      process.exit(0);
    });
    setTimeout(() => {
      log.warn("forced exit after drain timeout");
      process.exit(1);
    }, 10_000).unref();
  };
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

main();
