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
import { verifyHmac, selfTestHmac } from "./core/hmac.js";
import { RateLimiter } from "./rate-limit.js";
import { makePostgresLeadStore } from "./adapters/store-postgres.js";
import { makeJtJobtreadAdapter } from "./adapters/jt-jobtread.js";
import { makeNotifyHttpClient } from "./adapters/notify-http.js";
import { makeBridgeEmailClient } from "./adapters/email-bridge.js";
import { makePostgresReportStore } from "./adapters/store-reports-postgres.js";
import { buildNotificationInput } from "./core/notify-payload.js";
import { renderCustomerEmail } from "./core/customer-email.js";
import { buildReportFromLead } from "./core/build-report.js";
import type { LeadStore } from "./ports/store.js";
import type { ReportStore } from "./ports/reports.js";
import type { JtClient } from "./ports/jt.js";
import type { NotifyClient } from "./ports/notify.js";
import type { CustomerEmailClient } from "./ports/customer-email.js";

const MAX_BODY_BYTES = 64 * 1024;

/**
 * D33 — how long a same-source resubmission counts as "already acknowledged".
 * Chelsea Heveran's two calculator runs were 3 seconds apart; a duplicate
 * submission is minutes-scale, not months-scale. Kept short deliberately so a
 * returning customer with a new project still receives their summary — the
 * fingerprint identifies the person, and suppressing on identity alone would
 * silently stop emailing repeat customers, a worse failure than the one this
 * closes because nobody would ever see it.
 */
const DUP_ACK_WINDOW_HOURS = 48;

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

// async as of D33: the boot-time schema precondition must resolve BEFORE
// server.listen, or the service accepts captures during the window in which
// it cannot yet prove it can dedupe them.
async function main(): Promise<void> {
  const config = loadConfig();
  const log = makeStderrLogger({
    minLevel: config.logLevel,
    serviceName: config.serviceName,
  });

  // ── HMAC startup self-test ──
  // Fails loud (exit 1 → systemd unit failed) when the shared signing
  // secret is missing/short/broken. Catches half-rotations where n8n
  // and hwc-leads end up holding different bytes — that mode silently
  // 401s every lead until someone notices the empty dashboard.
  if (config.hmacSecret !== undefined) {
    const t = selfTestHmac(config.hmacSecret);
    if (!t.ok) {
      log.error(`[startup] FATAL: HMAC secret validation failed — lead submissions will 401`, {
        reason: t.reason,
      });
      process.exit(1);
    }
    log.info("[startup] HMAC secret self-test ok");
  } else {
    log.warn("[startup] HMAC secret unset — skipping self-test (DEV ONLY)");
  }

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

  // D33: refuse to run half-alive. Without hwc-crm migration 009 this service
  // still accepts leads perfectly well — it just silently mints a new case per
  // submission again, and nobody notices until a customer gets the same email
  // twice. A dependency that fails invisibly has to be checked at boot.
  try {
    await store.verifySchema();
  } catch (err) {
    log.error("schema precondition failed", {
      err: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  }

  const reportStore: ReportStore = makePostgresReportStore({
    dsn: config.postgresDsn,
    log: log.child({ component: "reports-store" }),
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

  // Transport-layer rate limiter — POST /leads only, keyed by source.
  const rateLimiter = new RateLimiter({
    maxPerWindow: config.rateLimit.maxPerWindow,
    windowSeconds: config.rateLimit.windowSeconds,
  });
  log.info("[http] rate limit configured", {
    maxPerWindow: config.rateLimit.maxPerWindow,
    windowSeconds: config.rateLimit.windowSeconds,
  });

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

        // ── 4a. Rate limit by source ──
        // Keyed on the validated LeadInput source so a misconfigured
        // calculator retry storm can't drag down contact submissions.
        const rl = rateLimiter.check(lead.payload.source);
        if (!rl.ok) {
          reqLog.warn(`[http] Rate limit exceeded for source=${lead.payload.source}, count=${rl.count}`);
          res.setHeader("retry-after", String(rl.retryAfterSeconds));
          writeJson(res, 429, {
            code: "RATE_LIMITED",
            error: "rate_limited",
            retryAfterSeconds: rl.retryAfterSeconds,
            message: `too many requests for source=${lead.payload.source}; retry in ${rl.retryAfterSeconds}s`,
          });
          return;
        }

        reqLog.info("lead accepted", {
          leadId: lead.id,
          source: lead.payload.source,
          contactEmail: lead.payload.contact.email,
        });

        // ── 5. Persist (Lead + Report in same tx when applicable) ──
        // buildReportFromLead returns undefined unless this is a
        // calculator submission with a reportId — only calculator leads
        // have a customer-facing report URL.
        const report = buildReportFromLead(lead);
        let saved;
        try {
          saved = await store.save(lead, report);
          reqLog.info(saved.inserted ? "lead persisted" : "lead deduped into existing case", {
            leadId: saved.leadId,
            submittedId: lead.id,
            reportId: report?.id,
          });
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

        // ── 5a. Which case did this submission land on? (D33) ──
        // Everything downstream — JT, notify, the customer email, the response
        // body — must address the RESOLVED case. lead.id names a row that was
        // never written when this was a repeat submission.
        const caseLead = { ...lead, id: saved.leadId };
        const caseId = saved.leadId;

        // Re-sending the T+0 acknowledgment is the thing the customer actually
        // experiences as "you emailed me twice", so it is gated on more than
        // just "we've seen this address". A fingerprint identifies a PERSON,
        // not a project: the same customer starting a genuinely new job months
        // later must still get their summary, or the site looks broken. Skip
        // only a same-source resubmission inside the window.
        const hoursSince = saved.existing
          ? (Date.now() - Date.parse(saved.existing.receivedAt)) / 3_600_000
          : Infinity;
        const suppressEmail =
          saved.existing !== undefined
          && saved.existing.source === lead.payload.source
          && hoursSince < DUP_ACK_WINDOW_HOURS;

        if (suppressEmail) {
          reqLog.info("suppressing duplicate T+0 ack", {
            leadId: caseId,
            source: lead.payload.source,
            hoursSinceLast: Math.round(hoursSince * 10) / 10,
          });
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
          // On a resubmission the case may already own a JT graph. createGraph
          // is idempotent on the ids it is GIVEN, so hand it what the existing
          // case has — passing {} would build a second JobTread job for the
          // same customer, the same duplication one layer over.
          const priorIds = saved.inserted
            ? {}
            : ((await store.byId(caseId).catch(() => undefined))?.jt ?? {});
          const result = await jt.createGraph(caseLead, priorIds);
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
              leadId: caseId,
              failedAt: result.failedAt,
              retryable: result.retryable,
              ids: jtIds,
            });
          }

          // Persist whatever happened.
          try {
            await store.updateJtIds(caseId, jtIds, nextStatus);
          } catch (err) {
            reqLog.error("jt id update failed", {
              leadId: caseId,
              err: err instanceof Error ? err.message : String(err),
            });
          }
        }

        // ── 7. hwc-notify ping ──
        // Pass the lead with its newly minted JT IDs so the
        // notification body can include the JT job deep-link.
        const leadWithJt = { ...caseLead, jt: jtIds };
        let notifyOk = false;
        let notifyMsg: string | undefined;
        try {
          const notifInput = buildNotificationInput(leadWithJt, undefined);
          const r = await notifyClient.send(notifInput);
          notifyOk = r.ok;
          notifyMsg = r.ok ? undefined : r.message;
          if (r.ok) {
            try { await store.markNotified(caseId); } catch { /* logged separately */ }
            reqLog.info("hwc-notify ping ok", { leadId: caseId, notificationId: r.notificationId });
          } else {
            reqLog.warn("hwc-notify ping failed", { leadId: caseId, err: r.message });
          }
        } catch (err) {
          notifyOk = false;
          notifyMsg = err instanceof Error ? err.message : String(err);
          reqLog.warn("hwc-notify ping threw", { leadId: caseId, err: notifyMsg });
        }

        // ── 8. Customer email ──
        let emailOk = false;
        let emailMsg: string | undefined;
        if (emailClient && !suppressEmail) {
          try {
            const rendered = renderCustomerEmail(leadWithJt);
            const r = await emailClient.send(rendered);
            emailOk = r.ok;
            emailMsg = r.ok ? undefined : r.message;
            if (r.ok) {
              try { await store.markEmailSent(caseId); } catch { /* logged separately */ }
              reqLog.info("customer email sent", { leadId: caseId, messageId: r.messageId });
            } else {
              reqLog.warn("customer email failed", { leadId: caseId, err: r.message });
            }
          } catch (err) {
            emailOk = false;
            emailMsg = err instanceof Error ? err.message : String(err);
            reqLog.warn("customer email threw", { leadId: caseId, err: emailMsg });
          }
        }

        writeJson(res, 202, {
          leadId: caseId,
          ...(saved.inserted ? {} : { duplicateOf: caseId, submittedId: lead.id }),
          source: lead.payload.source,
          status: nextStatus,
          receivedAt: lead.receivedAt,
          jt: jtIds,
          ...(jtError ? { jtError, jtRetryable } : {}),
          notify: { ok: notifyOk, ...(notifyMsg ? { message: notifyMsg } : {}) },
          email: !emailClient
            ? { ok: false, message: "disabled" }
            : suppressEmail
              ? { ok: false, message: "suppressed: duplicate submission" }
              : { ok: emailOk, ...(emailMsg ? { message: emailMsg } : {}) },
          message:
            "lead processed; partial-failure recovery via Phase 2.7 replay endpoint.",
        });
      })();
      return;
    }

    // ── GET /leads/:id ─────────────────────────────────────────────────
    {
      const m = /^\/leads\/([0-9a-f-]{36})$/.exec(url);
      if (method === "GET" && m && m[1]) {
        const leadId = m[1];
        void (async () => {
          try {
            const lead = await store.byId(leadId);
            if (!lead) {
              writeJson(res, 404, { code: "NOT_FOUND", message: `no lead with id ${leadId}` });
              return;
            }
            writeJson(res, 200, lead);
          } catch (err) {
            reqLog.error("byId query failed", {
              leadId,
              err: err instanceof Error ? err.message : String(err),
            });
            writeJson(res, 500, { code: "POSTGRES_ERROR", message: "lookup failed" });
          }
        })();
        return;
      }
    }

    // ── POST /leads/:id/replay ─────────────────────────────────────────
    // Resume the JT graph creation for a row whose previous attempt
    // landed at status=pending_jt. Idempotent: any step whose target
    // id is already set in the DB is skipped. Updates the row with
    // whatever NEW ids get created; status flips to "complete" once
    // every step is in place.
    {
      const m = /^\/leads\/([0-9a-f-]{36})\/replay$/.exec(url);
      if (method === "POST" && m && m[1]) {
        const leadId = m[1];
        void (async () => {
          try {
            const lead = await store.byId(leadId);
            if (!lead) {
              writeJson(res, 404, { code: "NOT_FOUND", message: `no lead with id ${leadId}` });
              return;
            }
            if (!jt) {
              writeJson(res, 503, {
                code: "JT_DISABLED",
                message: "jtGrantKey unwired — cannot replay",
              });
              return;
            }
            const existingIds = {
              ...(lead.jt.accountId  ? { accountId:  lead.jt.accountId  } : {}),
              ...(lead.jt.locationId ? { locationId: lead.jt.locationId } : {}),
              ...(lead.jt.contactId  ? { contactId:  lead.jt.contactId  } : {}),
              ...(lead.jt.jobId      ? { jobId:      lead.jt.jobId      } : {}),
            };
            const result = await jt.createGraph(lead, existingIds);
            const nextStatus = result.complete ? "complete" : "pending_jt";
            const newIds = {
              ...(result.ids.accountId  ? { accountId:  result.ids.accountId  } : {}),
              ...(result.ids.locationId ? { locationId: result.ids.locationId } : {}),
              ...(result.ids.contactId  ? { contactId:  result.ids.contactId  } : {}),
              ...(result.ids.jobId      ? { jobId:      result.ids.jobId      } : {}),
            };
            await store.updateJtIds(leadId, newIds, nextStatus);
            reqLog.info("lead replay", {
              leadId,
              previousStatus: lead.status,
              nextStatus,
              complete: result.complete,
            });
            writeJson(res, 200, {
              leadId,
              previousStatus: lead.status,
              status: nextStatus,
              jt: newIds,
              ...(result.complete ? {} : { failedAt: result.failedAt, jtError: result.error }),
            });
          } catch (err) {
            reqLog.error("replay failed", {
              leadId,
              err: err instanceof Error ? err.message : String(err),
            });
            writeJson(res, 500, {
              code: "REPLAY_ERROR",
              message: err instanceof Error ? err.message : String(err),
            });
          }
        })();
        return;
      }
    }

    // ── GET /api/reports/:id ───────────────────────────────────────────
    // Public-facing report viewer fetches this. Returns the sanitised
    // ReportPayload + templateId. 410 Gone when revoked. The site at
    // /report/<id> renders client-side from this response.
    //
    // Permissive id charset: alnum + dash to allow the 8-char [a-z0-9]
    // ids the calc generates plus future longer slugs without a
    // migration.
    //
    // CORS: the customer's browser is on https://iheartwoodcraft.com
    // (Hostinger) and this service is on the tailnet/Caddy host. Allow
    // the production origin so the report.njk fetch lands.
    {
      const m = /^\/api\/reports\/([A-Za-z0-9-]{4,64})$/.exec(url);
      if (method === "GET" && m && m[1]) {
        const reportId = m[1];
        void (async () => {
          try {
            res.setHeader("access-control-allow-origin", "https://iheartwoodcraft.com");
            res.setHeader("vary", "origin");
            const report = await reportStore.byId(reportId);
            if (!report) {
              writeJson(res, 404, { code: "NOT_FOUND", message: `no report with id ${reportId}` });
              return;
            }
            if (report.revokedAt) {
              writeJson(res, 410, {
                code: "REPORT_REVOKED",
                message: "this report has been revoked",
                revokedAt: report.revokedAt,
              });
              return;
            }
            // Fire-and-forget view tracking — don't block the response
            // on a single UPDATE. If it fails the report is still
            // served and the next view re-attempts.
            void reportStore.recordView(reportId).catch((err) => {
              reqLog.warn("[reports] recordView failed", {
                reportId,
                err: err instanceof Error ? err.message : String(err),
              });
            });
            writeJson(res, 200, {
              reportId: report.id,
              templateId: report.templateId,
              payload: report.payload,
              createdAt: report.createdAt,
            });
          } catch (err) {
            reqLog.error("[reports] byId query failed", {
              reportId,
              err: err instanceof Error ? err.message : String(err),
            });
            writeJson(res, 500, { code: "POSTGRES_ERROR", message: "report lookup failed" });
          }
        })();
        return;
      }
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
      try { await reportStore.close(); } catch { /* ignore */ }
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

main().catch((err: unknown) => {
  // Nothing above this point has a logger guaranteed to exist, so stderr it is.
  console.error("hwc-leads failed to start:", err);
  process.exit(1);
});
