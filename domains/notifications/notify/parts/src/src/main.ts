/**
 * hwc-notify — entry point.
 *
 * Phase 1.1: minimal HTTP server with /health only. Subsequent chunks add
 * core types, channel adapters, routing, and the real /notify endpoint.
 *
 * Shape mirrors persona-daemon/parts/src/main.ts: load config, build
 * adapters, wire shells, listen.
 */

import { createServer } from "node:http";
import { loadConfig } from "./config.ts";
import { makeStderrLogger } from "./adapters/log-stderr.ts";

function main(): void {
  const config = loadConfig();
  const log = makeStderrLogger({
    minLevel: config.logLevel,
    serviceName: config.serviceName,
  });

  const startedAt = new Date();

  const server = createServer((req, res) => {
    const url = req.url ?? "/";
    const method = req.method ?? "GET";

    // /health — liveness probe. No body parsing, no auth, fastest path.
    if (method === "GET" && url === "/health") {
      const body = JSON.stringify({
        status: "ok",
        service: config.serviceName,
        version: config.version,
        uptimeSeconds: Math.round((Date.now() - startedAt.getTime()) / 1000),
      });
      res.writeHead(200, {
        "content-type": "application/json",
        "content-length": Buffer.byteLength(body).toString(),
      });
      res.end(body);
      return;
    }

    // Everything else: 404 with a structured body so callers can match shape.
    const body = JSON.stringify({
      code: "NOT_FOUND",
      message: `no route: ${method} ${url}`,
    });
    res.writeHead(404, {
      "content-type": "application/json",
      "content-length": Buffer.byteLength(body).toString(),
    });
    res.end(body);
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
    // Hard cap on graceful drain — systemd's default TimeoutStopSec is 90s.
    setTimeout(() => {
      log.warn("forced exit after drain timeout");
      process.exit(1);
    }, 10_000).unref();
  };
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  process.on("SIGINT", () => shutdown("SIGINT"));
}

main();
