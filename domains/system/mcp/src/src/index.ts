/**
 * HWC Infrastructure MCP Server — entry point.
 *
 * Exposes NixOS system configuration and runtime state as MCP tools.
 * Supports three transports:
 *   - stdio (Claude Code, local)
 *   - Streamable HTTP (Claude.ai, remote — MCP spec 2025-06-18)
 *   - Legacy SSE (fallback for older clients)
 */

import { randomUUID } from "node:crypto";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { loadConfig } from "./config.js";
import { log, setLogLevel } from "./log.js";
import type { ResourceDef } from "./types.js";
import { ToolRegistry } from "./tools/registry.js";
import { allTools } from "./tools/index.js";
import { allResources } from "./resources/index.js";

// ── Server factory ──────────────────────────────────────────────────────
// Streamable HTTP needs a fresh Server+Transport pair per session.

function createMCPServer(
  registry: ToolRegistry,
  resources: ResourceDef[],
): Server {
  const server = new Server(
    { name: "hwc-sys-mcp", version: "0.1.0" },
    { capabilities: { tools: {}, resources: {} } },
  );

  const tools = registry.getAll();

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: tools.map((t) => ({
      name: t.name,
      description: t.description,
      inputSchema: t.inputSchema,
    })),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const toolName = request.params.name;
    const toolArgs = (request.params.arguments ?? {}) as Record<string, unknown>;
    const tool = tools.find((t) => t.name === toolName);

    if (!tool) {
      return {
        content: [{ type: "text", text: `Unknown tool: ${toolName}` }],
        isError: true,
      };
    }

    const startMs = Date.now();
    try {
      const result = await tool.handler(toolArgs);
      const durationMs = Date.now() - startMs;
      log.debug("Tool call completed", { tool: toolName, status: result.status, durationMs });

      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        isError: result.status === "error",
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      log.error("Tool call threw exception", {
        tool: toolName,
        error: message,
        durationMs: Date.now() - startMs,
      });
      return {
        content: [
          { type: "text", text: JSON.stringify({
            status: "error",
            message,
            error_type: "INTERNAL_ERROR",
            suggestion: "This is an unhandled exception. Check server logs for details.",
            error: message,
          }) },
        ],
        isError: true,
      };
    }
  });

  server.setRequestHandler(ListResourcesRequestSchema, async () => ({
    resources: resources.map((r) => ({
      uri: r.uri,
      name: r.name,
      description: r.description,
      mimeType: r.mimeType,
    })),
  }));

  server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
    const uri = request.params.uri;
    const resource = resources.find((r) => r.uri === uri);

    if (!resource) {
      throw new Error(`Unknown resource: ${uri}`);
    }

    const content = await resource.load();
    return {
      contents: [
        { uri: resource.uri, mimeType: resource.mimeType, text: content },
      ],
    };
  });

  return server;
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  const config = loadConfig();
  setLogLevel(config.logLevel);

  log.info("Starting HWC Infrastructure MCP Server", {
    transport: config.transport,
    logLevel: config.logLevel,
    hostname: config.hostname,
  });

  const registry = new ToolRegistry();
  registry.register(allTools(config));
  log.info("Tool registry loaded", { toolCount: registry.count() });

  const resources = allResources(config.nixosConfigPath);
  log.info("Resources loaded", { resourceCount: resources.length });

  // ── stdio transport ─────────────────────────────────────────────────
  if (config.transport === "stdio") {
    const server = createMCPServer(registry, resources);
    const transport = new StdioServerTransport();
    await server.connect(transport);
    log.info("HWC Infra MCP Server running on stdio");
    return;
  }

  // ── HTTP transport (SSE + Streamable HTTP) ──────────────────────────
  if (config.transport === "sse" || config.transport === "both") {
    const { createServer } = await import("node:http");
    const port = config.port;
    const host = config.host;

    // Session tracking for Streamable HTTP (one Server+Transport per session)
    const SESSION_TTL_MS = 30 * 60 * 1000; // 30 min — reap idle sessions
    const SESSION_REAP_INTERVAL_MS = 60 * 1000; // check every 60s
    const SSE_PING_INTERVAL_MS = 25 * 1000; // ping every 25s to keep proxies alive

    interface ManagedSession {
      server: Server;
      transport: StreamableHTTPServerTransport;
      lastActivity: number;
      pingInterval?: ReturnType<typeof setInterval>;
    }
    const sessions = new Map<string, ManagedSession>();

    // Clean up a session: stop pings, close transport/server, remove from map
    function cleanupSession(id: string, reason: string) {
      const session = sessions.get(id);
      if (!session) return;
      if (session.pingInterval) clearInterval(session.pingInterval);
      try { session.transport.close(); } catch { /* ignore */ }
      try { session.server.close(); } catch { /* ignore */ }
      sessions.delete(id);
      log.info("Session cleaned up", { sessionId: id, reason, activeSessions: sessions.size });
    }

    // Reap stale sessions periodically
    const reapInterval = setInterval(() => {
      const now = Date.now();
      for (const [id, session] of sessions) {
        if (now - session.lastActivity > SESSION_TTL_MS) {
          cleanupSession(id, `idle-${Math.round((now - session.lastActivity) / 1000)}s`);
        }
      }
    }, SESSION_REAP_INTERVAL_MS);
    reapInterval.unref(); // don't prevent process exit

    // Legacy SSE (single active connection)
    let legacySseTransport: SSEServerTransport | null = null;
    let legacySseServer: Server | null = null;

    const httpServer = createServer(async (req, res) => {
      const startMs = Date.now();
      const url = req.url || "/";
      const method = req.method || "?";
      const sessionId = req.headers["mcp-session-id"] as string | undefined;

      // Request logging — log every request for debugging flaky connections
      log.info("HTTP request", {
        method,
        url,
        sessionId: sessionId || "-",
        remoteAddr: req.socket.remoteAddress,
        accept: req.headers.accept || "-",
        contentType: req.headers["content-type"] || "-",
      });

      // Log response when finished
      res.on("finish", () => {
        const durationMs = Date.now() - startMs;
        if (durationMs > 100 || res.statusCode >= 400) {
          log.info("HTTP response", {
            method,
            url,
            status: res.statusCode,
            durationMs,
            sessionId: sessionId || "-",
          });
        }
      });

      // Log client disconnects — key signal for flaky Funnel connections
      res.on("close", () => {
        if (!res.writableFinished) {
          log.warn("Client disconnected mid-response", {
            method,
            url,
            sessionId: sessionId || "-",
            statusCode: res.statusCode,
            headersSent: res.headersSent,
            durationMs: Date.now() - startMs,
          });
        }
      });

      // CORS — required for browser-based MCP clients (Claude.ai)
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, HEAD, DELETE, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept, Mcp-Session-Id, Last-Event-ID");
      res.setHeader("Access-Control-Expose-Headers", "Mcp-Session-Id");

      if (method === "OPTIONS") {
        res.writeHead(204);
        res.end();
        return;
      }

      // Fix Accept header for MCP routes — the SDK requires BOTH application/json
      // AND text/event-stream (returns 406 otherwise). Claude.ai or the proxy chain
      // sometimes sends only one. Normalize it before the SDK sees the request.
      // Must modify rawHeaders (the raw array) because @hono/node-server reads those,
      // not the parsed req.headers object.
      if (url === "/mcp" || url === "/") {
        const accept = req.headers.accept || "";
        if (!accept.includes("application/json") || !accept.includes("text/event-stream")) {
          const fixed = "application/json, text/event-stream";
          req.headers.accept = fixed;
          // Also patch rawHeaders — @hono/node-server reads this array directly
          const idx = req.rawHeaders.findIndex(h => h.toLowerCase() === "accept");
          if (idx >= 0) {
            req.rawHeaders[idx + 1] = fixed;
          } else {
            req.rawHeaders.push("Accept", fixed);
          }
        }
      }

      try {
        await handleRequest(req, res, url, method, sessionId);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        log.error("Unhandled request error", { method, url, error: message });
        if (!res.headersSent) {
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Internal server error" }));
        }
      }
    });

    // Keep-alive tuning — prevent Tailscale proxy from timing out idle connections
    httpServer.keepAliveTimeout = 65_000; // slightly above typical 60s proxy timeout
    httpServer.headersTimeout = 70_000;
    httpServer.requestTimeout = 0; // no timeout on requests (MCP tool calls can be slow)

    async function handleRequest(
      req: import("node:http").IncomingMessage,
      res: import("node:http").ServerResponse,
      url: string,
      method: string,
      sessionId: string | undefined,
    ) {
      // ── JT .well-known stubs ─────────────────────────────────────
      // Claude.ai probes these during connection. Return clean 404.
      if (url.startsWith("/jt/.well-known/")) {
        res.writeHead(404);
        res.end();
        return;
      }

      // ── JT MCP proxy ──────────────────────────────────────────────
      // Forward /jt/* to the heartwood-mcp server on port 6102
      if (url.startsWith("/jt/") || url === "/jt") {
        const jtPort = parseInt(process.env.HWC_JT_MCP_PORT || "6102", 10);
        const strippedPath = url.slice(3) || "/";  // Remove "/jt" prefix
        const { request: httpRequest } = await import("node:http");

        const proxyReq = httpRequest({
          hostname: "127.0.0.1",
          port: jtPort,
          path: strippedPath,
          method,
          headers: {
            ...req.headers,
            host: `127.0.0.1:${jtPort}`,
          },
          timeout: 120_000, // 120s — JT MCP tool calls can be slow
        }, (proxyRes) => {
          res.writeHead(proxyRes.statusCode ?? 502, proxyRes.headers);
          proxyRes.pipe(res);
        });

        proxyReq.on("error", (err) => {
          log.error("JT MCP proxy error", { error: err.message, path: strippedPath });
          if (!res.headersSent) {
            res.writeHead(502, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: "JT MCP server unavailable" }));
          }
        });

        proxyReq.on("timeout", () => {
          log.error("JT MCP proxy timeout", { path: strippedPath, timeoutMs: 120_000 });
          proxyReq.destroy();
        });

        req.pipe(proxyReq);
        return;
      }

      // ── n8n .well-known stubs ────────────────────────────────────
      // Claude.ai probes these during connection. Return clean 404.
      if (url.startsWith("/n8n/.well-known/")) {
        res.writeHead(404);
        res.end();
        return;
      }

      // ── n8n MCP bridge proxy ──────────────────────────────────────
      // Forward /n8n/* to the n8n-mcp bridge on port 6201
      if (url.startsWith("/n8n/") || url === "/n8n") {
        const n8nPort = parseInt(process.env.HWC_N8N_MCP_PORT || "6201", 10);
        const n8nAuthToken = process.env.HWC_N8N_MCP_AUTH_TOKEN || "hwc-n8n-mcp-internal-bridge-token-do-not-expose-externally";
        const strippedPath = url.slice(4) || "/";  // Remove "/n8n" prefix
        const { request: httpRequest } = await import("node:http");

        const proxyReq = httpRequest({
          hostname: "127.0.0.1",
          port: n8nPort,
          path: strippedPath,
          method,
          headers: {
            ...req.headers,
            host: `127.0.0.1:${n8nPort}`,
            authorization: `Bearer ${n8nAuthToken}`,
          },
          timeout: 120_000, // 120s — n8n API calls (get_workflow full) can be slow
        }, (proxyRes) => {
          res.writeHead(proxyRes.statusCode ?? 502, proxyRes.headers);
          proxyRes.pipe(res);
        });

        proxyReq.on("error", (err) => {
          log.error("n8n MCP proxy error", { error: err.message, path: strippedPath });
          if (!res.headersSent) {
            res.writeHead(502, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: "n8n MCP bridge unavailable" }));
          }
        });

        proxyReq.on("timeout", () => {
          log.error("n8n MCP proxy timeout", { path: strippedPath, timeoutMs: 120_000 });
          proxyReq.destroy();
        });

        req.pipe(proxyReq);
        return;
      }

      // ── Health check ────────────────────────────────────────────────
      if (url === "/health" && method === "GET") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          status: "ok",
          server: "hwc-sys-mcp",
          version: "0.1.0",
          tools: registry.count(),
          resources: resources.length,
          uptime: process.uptime(),
          activeSessions: sessions.size,
          sessionIds: [...sessions.keys()],
          sessionAges: [...sessions.entries()].map(([id, s]) => ({
            id: id.slice(0, 8),
            idleSec: Math.round((Date.now() - s.lastActivity) / 1000),
          })),
        }));
        return;
      }

      // ── Streamable HTTP (MCP spec 2025-06-18) ───────────────────────
      // Handles POST (JSON-RPC), GET (SSE stream), DELETE (session close)
      if (url === "/mcp" || url === "/") {
        // Route to existing session
        if (sessionId && sessions.has(sessionId)) {
          const session = sessions.get(sessionId)!;
          session.lastActivity = Date.now();

          // SSE GET stream — start ping keepalive to prevent proxy timeouts.
          // Writes `: ping\n\n` (SSE comment, ignored by clients) every 25s.
          // If the write fails, the connection is dead — clean up the session.
          if (method === "GET") {
            // Clear any previous ping (client reconnected)
            if (session.pingInterval) clearInterval(session.pingInterval);
            session.pingInterval = setInterval(() => {
              try {
                const ok = res.write(": ping\n\n");
                if (ok === false) {
                  // Backpressure/closed — connection is dead
                  cleanupSession(sessionId!, "ping-backpressure");
                }
              } catch {
                cleanupSession(sessionId!, "ping-write-error");
              }
            }, SSE_PING_INTERVAL_MS);

            // Stop pinging when the SSE stream closes
            res.on("close", () => {
              if (session.pingInterval) {
                clearInterval(session.pingInterval);
                session.pingInterval = undefined;
              }
            });
          }

          await session.transport.handleRequest(req, res);
          return;
        }

        // New session — must be a POST with initialize
        if (method === "POST") {
          const body = await readBody(req);
          let parsed: unknown;
          try {
            parsed = JSON.parse(body);
          } catch {
            res.writeHead(400, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: "Invalid JSON" }));
            return;
          }

          // Check if this is an initialization request
          const isInit = isInitializeRequest(parsed);
          if (!isInit && !sessionId) {
            res.writeHead(400, { "Content-Type": "application/json" });
            res.end(JSON.stringify({
              jsonrpc: "2.0",
              error: { code: -32000, message: "Bad Request: No valid session ID and not an initialize request" },
              id: null,
            }));
            return;
          }

          // Create new session — sessionId is assigned inside handleRequest
          // when the transport processes the initialize message, so we use
          // onsessioninitialized to register it in our session map.
          const transport = new StreamableHTTPServerTransport({
            sessionIdGenerator: () => randomUUID(),
            enableJsonResponse: true,
            onsessioninitialized: (newSessionId) => {
              sessions.set(newSessionId, { server, transport, lastActivity: Date.now() });
              log.info("Streamable HTTP session created", {
                sessionId: newSessionId,
                activeSessions: sessions.size,
              });

              transport.onclose = () => {
                cleanupSession(newSessionId, "transport-close");
              };
            },
          });
          const server = createMCPServer(registry, resources);
          await server.connect(transport);

          // Handle the request with pre-parsed body
          await transport.handleRequest(req, res, parsed);
          return;
        }

        // GET without session (SSE stream) — need session first
        if (method === "GET" && !sessionId) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Session ID required for GET SSE stream" }));
          return;
        }

        // Unknown session — log it, this is a key flakiness indicator
        if (sessionId) {
          log.warn("Request for unknown session", { sessionId, method });
          res.writeHead(404, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Session not found" }));
          return;
        }

        res.writeHead(405, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Method not allowed" }));
        return;
      }

      // ── Legacy SSE (for older clients) ──────────────────────────────
      if (url === "/sse" && method === "GET") {
        // Clean up previous connection
        if (legacySseTransport) {
          try { await legacySseTransport.close(); } catch { /* ignore */ }
        }
        if (legacySseServer) {
          try { await legacySseServer.close(); } catch { /* ignore */ }
        }

        const transport = new SSEServerTransport("/messages", res);
        const server = createMCPServer(registry, resources);
        legacySseTransport = transport;
        legacySseServer = server;
        await server.connect(transport);
        log.info("Legacy SSE connection established");
        return;
      }

      if (url?.startsWith("/messages") && method === "POST") {
        if (!legacySseTransport) {
          res.writeHead(503, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "No active SSE connection" }));
          return;
        }
        await legacySseTransport.handlePostMessage(req, res);
        return;
      }

      // ── OAuth discovery stubs ──────────────────────────────────────
      // Claude.ai probes these during connection. Return proper 404 so
      // the client knows auth is not required (no WWW-Authenticate header).
      if (url?.startsWith("/.well-known/")) {
        res.writeHead(404);
        res.end();
        return;
      }

      // ── 404 ─────────────────────────────────────────────────────────
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        error: "Not found",
        endpoints: ["/mcp", "/jt/mcp", "/n8n/mcp", "/sse", "/messages", "/health"],
      }));
    }

    // Graceful shutdown — close all sessions, stop reaper
    function gracefulShutdown(signal: string) {
      log.info("Shutting down", { signal, activeSessions: sessions.size });
      clearInterval(reapInterval);
      for (const id of [...sessions.keys()]) {
        cleanupSession(id, `shutdown-${signal}`);
      }
      httpServer.close();
    }
    process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
    process.on("SIGINT", () => gracefulShutdown("SIGINT"));

    httpServer.on("error", (err) => {
      log.error("HTTP server error", { error: err.message });
    });

    httpServer.listen(port, host, () => {
      log.info(`HWC System MCP server listening on ${host}:${port}`, {
        streamableHttp: "/mcp",
        jtProxy: "/jt/mcp",
        n8nProxy: "/n8n/mcp",
        legacySse: "/sse",
        health: "/health",
        sessionTtlMin: SESSION_TTL_MS / 60_000,
      });
    });
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────

function readBody(req: import("node:http").IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString()));
    req.on("error", reject);
  });
}

function isInitializeRequest(parsed: unknown): boolean {
  if (Array.isArray(parsed)) {
    return parsed.some(
      (msg) => typeof msg === "object" && msg !== null && (msg as Record<string, unknown>).method === "initialize",
    );
  }
  return typeof parsed === "object" && parsed !== null && (parsed as Record<string, unknown>).method === "initialize";
}

main().catch((error) => {
  log.error("Fatal error", {
    error: error instanceof Error ? error.message : String(error),
  });
  process.exit(1);
});
