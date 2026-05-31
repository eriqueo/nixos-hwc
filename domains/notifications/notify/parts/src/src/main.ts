/**
 * hwc-notify — entry point.
 *
 * Phase 1.3 wiring:
 *   1. loadConfig()            — env + runtime-config.json
 *   2. buildChannels()         — channel instances from the data table
 *   3. mounted shells:
 *        GET  /health          — liveness, with channel + route summary
 *        POST /notify          — schema-validated, routed dispatch
 *
 * Adding a channel or routing rule is now a Nix-only change: append to
 * parts/channels.nix or parts/routes.nix, `nixos-rebuild switch`, done.
 */

import { readFileSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { loadConfig, type ServiceConfig } from "./config.js";
import { makeStderrLogger } from "./adapters/log-stderr.js";
import { makeDiscordChannel } from "./adapters/channel-discord.js";
import { makeLogOnlyChannel } from "./adapters/channel-logonly.js";
import { makeSmtpChannel } from "./adapters/channel-smtp.js";
import { safeParseNotificationInput } from "./schemas/notification.js";
import { AlertmanagerWebhookSchema } from "./schemas/alertmanager.js";
import { dispatch } from "./core/dispatch.js";
import { route } from "./core/router.js";
import { webhookToNotifications } from "./core/from-alertmanager.js";
import type { Notification } from "./core/types.js";
import type { Channel } from "./ports/channel.js";
import type { Logger } from "./ports/log.js";
import type { ChannelConfig } from "./schemas/runtime-config.js";

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

function statusFromDispatch(attempted: number, succeeded: number): number {
  if (attempted === 0) return 202;
  if (succeeded === attempted) return 200;
  if (succeeded === 0) return 502;
  return 207;
}

/** Read the secret file for a discord channel; trim trailing whitespace. */
function loadSecret(filepath: string): string {
  return readFileSync(filepath, "utf8").replace(/\s+$/u, "");
}

/** Materialize one ChannelConfig into a Channel instance. */
function buildChannel(cfg: ChannelConfig, log: Logger): Channel {
  switch (cfg.adapter) {
    case "discord": {
      const webhookUrl = loadSecret(cfg.params.secretFile);
      return makeDiscordChannel({
        id: cfg.id,
        name: cfg.name,
        webhookUrl,
        username: cfg.params.username,
        timeoutMs: cfg.params.timeoutMs,
      });
    }
    case "smtp":
      return makeSmtpChannel({
        id: cfg.id,
        name: cfg.name,
        params: cfg.params,
      });
    case "log-only":
      return makeLogOnlyChannel({
        id: cfg.id,
        name: cfg.name,
        log: log.child({ channel: cfg.id }),
      });
  }
}

/** Build all channels and return them keyed by id for routing lookup. */
function buildChannelMap(
  config: ServiceConfig,
  log: Logger,
): Map<string, Channel> {
  const map = new Map<string, Channel>();
  for (const cfg of config.runtimeConfig.channels) {
    try {
      map.set(cfg.id, buildChannel(cfg, log));
    } catch (err) {
      // A channel that won't construct (e.g., secret file unreadable)
      // shouldn't crash the whole service — fall back to log-only so
      // routes referencing this id still succeed at the contract level.
      const reason = err instanceof Error ? err.message : String(err);
      log.error("channel build failed; substituting log-only", {
        channelId: cfg.id,
        adapter: cfg.adapter,
        err: reason,
      });
      map.set(
        cfg.id,
        makeLogOnlyChannel({
          id: cfg.id,
          name: `${cfg.name} (FAILED INIT — log-only)`,
          log: log.child({ channel: cfg.id, degraded: true }),
        }),
      );
    }
  }
  return map;
}

function main(): void {
  const config = loadConfig();
  const log = makeStderrLogger({
    minLevel: config.logLevel,
    serviceName: config.serviceName,
  });

  const channelMap = buildChannelMap(config, log);
  log.info("runtime config loaded", {
    runtimeConfigFile: config.runtimeConfigFile,
    channels: [...channelMap.values()].map((c) => ({ id: c.id, adapter: c.adapter })),
    routes: config.runtimeConfig.routes.length,
    defaultChannels: config.runtimeConfig.defaultChannels,
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
        channels: [...channelMap.values()].map((c) => ({
          id: c.id,
          name: c.name,
          adapter: c.adapter,
        })),
        routes: config.runtimeConfig.routes.length,
        defaultChannels: config.runtimeConfig.defaultChannels,
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
        const decision = route(
          notif,
          config.runtimeConfig.routes,
          config.runtimeConfig.defaultChannels,
        );
        const targets = decision.channelIds
          .map((id) => channelMap.get(id))
          .filter((c): c is Channel => c !== undefined);

        reqLog.info("dispatching notification", {
          notificationId: notif.id,
          topic: notif.topic,
          priority: notif.priority,
          source: notif.source,
          matchedRule: decision.matchedRule,
          channelIds: targets.map((c) => c.id),
        });

        const result = await dispatch(notif, targets);
        reqLog.info("dispatch complete", {
          notificationId: notif.id,
          attempted: result.attempted,
          succeeded: result.succeeded,
          failed: result.failed,
        });

        writeJson(res, statusFromDispatch(result.attempted, result.succeeded), {
          ...result,
          matchedRule: decision.matchedRule,
        });
      })();
      return;
    }

    // ── POST /webhook/alertmanager ─────────────────────────────────────
    if (method === "POST" && url === "/webhook/alertmanager") {
      void (async () => {
        let raw: unknown;
        try {
          raw = await readJsonBody(req);
        } catch (err) {
          reqLog.warn("alertmanager body parse error", {
            err: err instanceof Error ? err.message : String(err),
          });
          writeJson(res, 400, {
            code: "VALIDATION_ERROR",
            message: err instanceof Error ? err.message : "invalid request body",
          });
          return;
        }

        const parsed = AlertmanagerWebhookSchema.safeParse(raw);
        if (!parsed.success) {
          reqLog.warn("alertmanager schema validation failed", { issues: parsed.error.issues });
          writeJson(res, 400, {
            code: "VALIDATION_ERROR",
            message: "Alertmanager webhook schema validation failed",
            issues: parsed.error.issues,
          });
          return;
        }

        const notifs: Notification[] = webhookToNotifications(parsed.data);
        reqLog.info("alertmanager batch received", {
          alertCount: parsed.data.alerts.length,
          batchStatus: parsed.data.status,
          receiver: parsed.data.receiver,
        });

        // Dispatch each alert as its own notification, in parallel.
        // We collect per-notification results into a single response so
        // Alertmanager can see the aggregate outcome.
        const perAlert = await Promise.all(
          notifs.map(async (notif) => {
            const decision = route(
              notif,
              config.runtimeConfig.routes,
              config.runtimeConfig.defaultChannels,
            );
            const targets = decision.channelIds
              .map((id) => channelMap.get(id))
              .filter((c): c is NonNullable<typeof c> => c !== undefined);
            const result = await dispatch(notif, targets);
            // result already contains notificationId; we add the
            // alert-friendly summary fields alongside it.
            return {
              ...result,
              title: notif.title,
              priority: notif.priority,
              matchedRule: decision.matchedRule,
            };
          }),
        );

        const totalAttempted = perAlert.reduce((s, p) => s + p.attempted, 0);
        const totalSucceeded = perAlert.reduce((s, p) => s + p.succeeded, 0);
        const totalFailed = totalAttempted - totalSucceeded;

        reqLog.info("alertmanager batch dispatch complete", {
          alerts: notifs.length,
          totalAttempted,
          totalSucceeded,
          totalFailed,
        });

        writeJson(res, statusFromDispatch(totalAttempted, totalSucceeded), {
          alerts: notifs.length,
          totalAttempted,
          totalSucceeded,
          totalFailed,
          perAlert,
        });
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
