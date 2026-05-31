/**
 * hwc-notify — entry point.
 *
 * Phase 1.2:
 *   GET  /health                — liveness probe
 *   POST /notify                — schema-validated dispatch
 *
 * Hexagonal wiring at startup:
 *   1. loadConfig()             — env + secret files
 *   2. build adapters            — Discord + LogOnly today
 *   3. build the channel list   — for now, hand-wired; routing data
 *                                  arrives in Phase 1.3
 *   4. listen
 *
 * Phase 1.3 will introduce a router that picks a per-notification
 * channel subset from declarative routing rules; for now /notify
 * sends to every configured channel.
 */

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { loadConfig, type ServiceConfig } from "./config.js";
import { makeStderrLogger } from "./adapters/log-stderr.js";
import { makeDiscordChannel } from "./adapters/channel-discord.js";
import { makeLogOnlyChannel } from "./adapters/channel-logonly.js";
import { safeParseNotificationInput } from "./schemas/notification.js";
import { dispatch } from "./core/dispatch.js";
import type { Channel } from "./ports/channel.js";
import type { Logger } from "./ports/log.js";

/** Body cap on POST /notify — generous but bounded. */
const MAX_BODY_BYTES = 32 * 1024;

async function readJsonBody(req: IncomingMessage): Promise<unknown> {
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
    req.on("end", () => {
      if (chunks.length === 0) {
        resolve(null);
        return;
      }
      const text = Buffer.concat(chunks).toString("utf8");
      try {
        resolve(JSON.parse(text));
      } catch (err) {
        reject(new Error(`invalid JSON body: ${err instanceof Error ? err.message : String(err)}`));
      }
    });
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

/** Pick HTTP status from the dispatch result. */
function statusFromDispatch(attempted: number, succeeded: number): number {
  if (attempted === 0) return 202; // accepted, nowhere to send (config issue, not a client error)
  if (succeeded === attempted) return 200;
  if (succeeded === 0) return 502;
  return 207; // multi-status: partial success
}

function buildChannels(config: ServiceConfig, log: Logger): Channel[] {
  const channels: Channel[] = [];

  if (config.discordAlertsWebhookUrl) {
    channels.push(
      makeDiscordChannel({
        id: "discord-hwc-alerts",
        name: "#hwc-alerts (Discord)",
        username: "HWC Alerts",
        webhookUrl: config.discordAlertsWebhookUrl,
      }),
    );
  } else {
    log.warn("discord-hwc-alerts not wired (HWC_NOTIFY_DISCORD_ALERTS_FILE missing); falling back to log-only");
    channels.push(
      makeLogOnlyChannel({
        id: "discord-hwc-alerts",
        name: "#hwc-alerts (DISABLED — log-only)",
        log: log.child({ channel: "discord-hwc-alerts" }),
      }),
    );
  }

  return channels;
}

function main(): void {
  const config = loadConfig();
  const log = makeStderrLogger({
    minLevel: config.logLevel,
    serviceName: config.serviceName,
  });

  const channels = buildChannels(config, log);
  log.info("channels wired", {
    count: channels.length,
    channels: channels.map((c) => ({ id: c.id, adapter: c.adapter })),
  });

  const startedAt = new Date();

  const server = createServer((req, res) => {
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
        channels: channels.map((c) => ({ id: c.id, adapter: c.adapter })),
      });
      return;
    }

    // ── POST /notify ───────────────────────────────────────────────────
    if (method === "POST" && url === "/notify") {
      void (async () => {
        let raw: unknown;
        try {
          raw = await readJsonBody(req);
        } catch (err) {
          reqLog.warn("body parse error", { err: err instanceof Error ? err.message : String(err) });
          writeJson(res, 400, {
            code: "VALIDATION_ERROR",
            message: err instanceof Error ? err.message : "invalid request body",
          });
          return;
        }

        const parsed = safeParseNotificationInput(raw);
        if (!parsed.ok) {
          reqLog.warn("schema validation failed", { issues: parsed.issues });
          writeJson(res, 400, {
            code: "VALIDATION_ERROR",
            message: "Notification schema validation failed",
            issues: parsed.issues,
          });
          return;
        }

        const notif = parsed.value;
        reqLog.info("dispatching notification", {
          notificationId: notif.id,
          topic: notif.topic,
          priority: notif.priority,
          source: notif.source,
        });

        const result = await dispatch(notif, channels);
        reqLog.info("dispatch complete", {
          notificationId: notif.id,
          attempted: result.attempted,
          succeeded: result.succeeded,
          failed: result.failed,
        });

        writeJson(res, statusFromDispatch(result.attempted, result.succeeded), result);
      })();
      return;
    }

    // ── 404 ────────────────────────────────────────────────────────────
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
    log.info("hwc-notify listening", {
      bindAddr: config.bindAddr,
      port: config.port,
      logLevel: config.logLevel,
    });
  });

  // SIGTERM from systemd: stop accepting, drain in-flight, exit.
  const shutdown = (signal: string): void => {
    log.info("shutdown signal received", { signal });
    server.close((err) => {
      if (err) log.error("server close error", { err: String(err) });
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
