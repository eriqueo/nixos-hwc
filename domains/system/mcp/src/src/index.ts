/**
 * HWC Infrastructure MCP Gateway — unified entry point.
 *
 * Single Streamable HTTP transport serving tools from:
 *   - hwc-sys (local, in-process): NixOS config + runtime tools
 *   - heartwood-mcp (stdio backend): 63 JobTread PAVE tools
 *   - n8n-mcp (stdio backend): workflow automation tools
 *
 * Transports:
 *   - stdio  (Claude Code, local)
 *   - Streamable HTTP (Claude.ai, remote — MCP spec 2025-06-18)
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
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";

import { loadConfig } from "./config.js";
import { log, setLogLevel } from "./log.js";
import type { ResourceDef } from "./types.js";
import { ToolRegistry } from "./tools/registry.js";
import { allTools } from "./tools/index.js";
import { allResources } from "./resources/index.js";
import { BackendManager } from "./backend-manager.js";
import { StdioBackend } from "./stdio-backend.js";

// ── Server factory ──────────────────────────────────────────────────────
// Streamable HTTP needs a fresh Server+Transport pair per session.

function createMCPServer(
  backendManager: BackendManager,
  resources: ResourceDef[],
): Server {
  const server = new Server(
    { name: "hwc-sys-mcp", version: "0.2.0" },
    { capabilities: { tools: {}, resources: {} } },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: backendManager.allTools().map((t) => ({
      name: t.name,
      description: t.description,
      inputSchema: t.inputSchema,
    })),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const toolName = request.params.name;
    const toolArgs = (request.params.arguments ?? {}) as Record<string, unknown>;
    return backendManager.callTool(toolName, toolArgs);
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

// ── Backend configuration from environment ──────────────────────────────

function buildBackends(): StdioBackend[] {
  const backends: StdioBackend[] = [];
  const nodePath = process.env.HWC_NODE_PATH || "node";

  // heartwood-mcp (JobTread tools) — spawned as stdio child
  const jtSrcDir = process.env.HWC_JT_SRC_DIR;
  if (jtSrcDir) {
    backends.push(new StdioBackend({
      name: "heartwood-mcp",
      command: nodePath,
      args: [`${jtSrcDir}/dist/index.js`],
      env: {
        TRANSPORT: "stdio",
        JT_GRANT_KEY: process.env.JT_GRANT_KEY || "",
        JT_ORG_ID: process.env.JT_ORG_ID || "22Nm3uFevXMb",
        JT_USER_ID: process.env.JT_USER_ID || "22Nm3uFeRB7s",
        JT_API_URL: process.env.JT_API_URL || "https://api.jobtread.com/pave",
        LOG_LEVEL: process.env.HWC_MCP_LOG_LEVEL || "info",
        NODE_ENV: "production",
      },
      cwd: jtSrcDir,
      callTimeoutMs: 60_000, // JT API calls can be slow
    }));
    log.info("Configured heartwood-mcp backend", { srcDir: jtSrcDir });
  } else {
    log.info("heartwood-mcp backend skipped (HWC_JT_SRC_DIR not set)");
  }

  // n8n-mcp (workflow automation tools) — spawned as stdio child
  const n8nEntryPoint = process.env.HWC_N8N_ENTRY_POINT;
  if (n8nEntryPoint) {
    backends.push(new StdioBackend({
      name: "n8n-mcp",
      command: nodePath,
      args: [n8nEntryPoint],
      env: {
        MCP_MODE: "stdio",
        N8N_API_KEY: process.env.N8N_API_KEY || "",
        N8N_API_URL: process.env.N8N_API_URL || "http://localhost:5678",
        N8N_API_TIMEOUT: "60000",
        LOG_LEVEL: process.env.HWC_MCP_LOG_LEVEL || "info",
        NODE_ENV: "production",
      },
      callTimeoutMs: 60_000, // n8n API calls can be slow
    }));
    log.info("Configured n8n-mcp backend", { entryPoint: n8nEntryPoint });
  } else {
    log.info("n8n-mcp backend skipped (HWC_N8N_ENTRY_POINT not set)");
  }

  return backends;
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  const config = loadConfig();
  setLogLevel(config.logLevel);

  log.info("Starting HWC Infrastructure MCP Gateway", {
    transport: config.transport,
    logLevel: config.logLevel,
    hostname: config.hostname,
    version: "0.2.0",
  });

  // Build local tool registry (hwc-sys tools)
  const registry = new ToolRegistry();
  registry.register(allTools(config));
  log.info("Local tools loaded", { count: registry.count() });

  const resources = allResources(config.nixosConfigPath);

  // Build backend manager — aggregates local + stdio backends
  const manager = new BackendManager();
  manager.registerLocal(registry.getAll());

  const backends = buildBackends();
  for (const b of backends) {
    manager.addBackend(b);
  }

  // Start all stdio backends (non-fatal failures — partial startup)
  await manager.startAll();

  // ── stdio transport ─────────────────────────────────────────────────
  if (config.transport === "stdio") {
    const server = createMCPServer(manager, resources);
    const transport = new StdioServerTransport();
    await server.connect(transport);
    log.info("HWC Gateway running on stdio");

    // Graceful shutdown for stdio
    const shutdown = async () => {
      await manager.stopAll();
      process.exit(0);
    };
    process.on("SIGTERM", shutdown);
    process.on("SIGINT", shutdown);
    return;
  }

  // ── HTTP transport (Streamable HTTP) ────────────────────────────────
  if (config.transport === "sse" || config.transport === "both") {
    const { createServer } = await import("node:http");
    const port = config.port;
    const host = config.host;

    // Session tracking (one Server+Transport per session)
    const SESSION_TTL_MS = 30 * 60 * 1000; // 30 min
    const SESSION_REAP_INTERVAL_MS = 60 * 1000;
    const SSE_PING_INTERVAL_MS = 25 * 1000;

    interface ManagedSession {
      server: Server;
      transport: StreamableHTTPServerTransport;
      lastActivity: number;
      pingInterval?: ReturnType<typeof setInterval>;
    }
    const sessions = new Map<string, ManagedSession>();

    function cleanupSession(id: string, reason: string) {
      const session = sessions.get(id);
      if (!session) return;
      if (session.pingInterval) clearInterval(session.pingInterval);
      try { session.transport.close(); } catch { /* ignore */ }
      try { session.server.close(); } catch { /* ignore */ }
      sessions.delete(id);
      log.info("Session cleaned up", { sessionId: id, reason, activeSessions: sessions.size });
    }

    const reapInterval = setInterval(() => {
      const now = Date.now();
      for (const [id, session] of sessions) {
        if (now - session.lastActivity > SESSION_TTL_MS) {
          cleanupSession(id, `idle-${Math.round((now - session.lastActivity) / 1000)}s`);
        }
      }
    }, SESSION_REAP_INTERVAL_MS);
    reapInterval.unref();

    const httpServer = createServer(async (req, res) => {
      const startMs = Date.now();
      const url = req.url || "/";
      const method = req.method || "?";
      const sessionId = req.headers["mcp-session-id"] as string | undefined;

      log.info("HTTP request", {
        method,
        url,
        sessionId: sessionId || "-",
        remoteAddr: req.socket.remoteAddress,
        accept: req.headers.accept || "-",
        contentType: req.headers["content-type"] || "-",
      });

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

      // CORS
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, HEAD, DELETE, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept, Mcp-Session-Id, Last-Event-ID");
      res.setHeader("Access-Control-Expose-Headers", "Mcp-Session-Id");

      if (method === "OPTIONS") {
        res.writeHead(204);
        res.end();
        return;
      }

      // Fix Accept header — SDK requires both application/json AND text/event-stream
      if (url === "/mcp" || url === "/") {
        const accept = req.headers.accept || "";
        if (!accept.includes("application/json") || !accept.includes("text/event-stream")) {
          const fixed = "application/json, text/event-stream";
          req.headers.accept = fixed;
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

    httpServer.keepAliveTimeout = 65_000;
    httpServer.headersTimeout = 70_000;
    httpServer.requestTimeout = 0;

    async function handleRequest(
      req: import("node:http").IncomingMessage,
      res: import("node:http").ServerResponse,
      url: string,
      method: string,
      sessionId: string | undefined,
    ) {
      // ── Health check ────────────────────────────────────────────────
      if (url === "/health" && method === "GET") {
        const backendHealth = manager.healthReport();
        const allToolsList = manager.allTools();
        const toolsBySource: Record<string, number> = {};
        for (const t of allToolsList) {
          toolsBySource[t.source] = (toolsBySource[t.source] || 0) + 1;
        }

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          status: "ok",
          server: "hwc-sys-mcp",
          version: "0.2.0",
          tools: allToolsList.length,
          toolsBySource,
          resources: resources.length,
          backends: backendHealth,
          uptime: process.uptime(),
          activeSessions: sessions.size,
          sessionAges: [...sessions.entries()].map(([id, s]) => ({
            id: id.slice(0, 8),
            idleSec: Math.round((Date.now() - s.lastActivity) / 1000),
          })),
        }));
        return;
      }

      // ── Streamable HTTP (MCP spec 2025-06-18) ───────────────────────
      if (url === "/mcp" || url === "/") {
        // Route to existing session
        if (sessionId && sessions.has(sessionId)) {
          const session = sessions.get(sessionId)!;
          session.lastActivity = Date.now();

          // SSE GET stream — ping keepalive
          if (method === "GET") {
            if (session.pingInterval) clearInterval(session.pingInterval);
            session.pingInterval = setInterval(() => {
              try {
                const ok = res.write(": ping\n\n");
                if (ok === false) {
                  cleanupSession(sessionId!, "ping-backpressure");
                }
              } catch {
                cleanupSession(sessionId!, "ping-write-error");
              }
            }, SSE_PING_INTERVAL_MS);

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

        // New session — must be POST with initialize
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

          const transport = new StreamableHTTPServerTransport({
            sessionIdGenerator: () => randomUUID(),
            enableJsonResponse: true,
            onsessioninitialized: (newSessionId) => {
              sessions.set(newSessionId, { server, transport, lastActivity: Date.now() });
              log.info("Session created", {
                sessionId: newSessionId,
                activeSessions: sessions.size,
                totalTools: manager.allTools().length,
              });

              transport.onclose = () => {
                cleanupSession(newSessionId, "transport-close");
              };
            },
          });
          const server = createMCPServer(manager, resources);
          await server.connect(transport);

          await transport.handleRequest(req, res, parsed);
          return;
        }

        // GET without session
        if (method === "GET" && !sessionId) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Session ID required for GET SSE stream" }));
          return;
        }

        // Unknown session
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

      // ── OAuth discovery stubs ──────────────────────────────────────
      if (url?.startsWith("/.well-known/")) {
        res.writeHead(404);
        res.end();
        return;
      }

      // ── 404 ─────────────────────────────────────────────────────────
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        error: "Not found",
        endpoints: ["/mcp", "/health"],
      }));
    }

    // Graceful shutdown
    function gracefulShutdown(signal: string) {
      log.info("Shutting down", { signal, activeSessions: sessions.size });
      clearInterval(reapInterval);
      for (const id of [...sessions.keys()]) {
        cleanupSession(id, `shutdown-${signal}`);
      }
      manager.stopAll().then(() => {
        httpServer.close();
      });
    }
    process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
    process.on("SIGINT", () => gracefulShutdown("SIGINT"));

    httpServer.on("error", (err) => {
      log.error("HTTP server error", { error: err.message });
    });

    httpServer.listen(port, host, () => {
      log.info(`HWC Gateway listening on ${host}:${port}`, {
        streamableHttp: "/mcp",
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
