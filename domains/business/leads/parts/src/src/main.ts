/**
 * hwc-leads — entry point.
 *
 * Phase 2.1 wiring:
 *   GET  /health     — liveness + downstream service refs
 *   POST /leads      — returns 501 Not Implemented (Phase 2.2 lands the real
 *                      Lead schema + JT/Postgres/Notify dispatch path)
 *
 * Same shape as hwc-notify's main.ts: loadConfig → build adapters → mount
 * shells → listen. Subsequent chunks add the lead pipeline incrementally.
 */

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { loadConfig } from "./config.js";
import { makeStderrLogger } from "./adapters/log-stderr.js";

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

  // Visible at startup: which downstream creds are wired, without
  // ever logging the secret values themselves.
  log.info("hwc-leads starting", {
    bindAddr: config.bindAddr,
    port: config.port,
    logLevel: config.logLevel,
    notifyServiceUrl: config.notifyServiceUrl,
    hmacWired: config.hmacSecret !== undefined,
    jtGrantWired: config.jtGrantKey !== undefined,
  });

  const startedAt = new Date();

  const server = createServer((req: IncomingMessage, res: ServerResponse) => {
    const url = req.url ?? "/";
    const method = req.method ?? "GET";

    if (method === "GET" && url === "/health") {
      writeJson(res, 200, {
        status: "ok",
        service: config.serviceName,
        version: config.version,
        uptimeSeconds: Math.round((Date.now() - startedAt.getTime()) / 1000),
        // Surface the downstream config so /health doubles as a wiring check.
        downstream: {
          notifyServiceUrl: config.notifyServiceUrl,
          hmacWired: config.hmacSecret !== undefined,
          jtGrantWired: config.jtGrantKey !== undefined,
        },
      });
      return;
    }

    if (method === "POST" && url === "/leads") {
      writeJson(res, 501, {
        code: "NOT_IMPLEMENTED",
        message:
          "POST /leads ships in Phase 2.2 — Zod schema, HMAC verify, " +
          "JT graph creation, Postgres write, hwc-notify ping, customer email.",
      });
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
