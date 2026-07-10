/**
 * HWC Infrastructure MCP Gateway — unified entry point.
 *
 * Per-session Streamable HTTP transport serving tools from:
 *   - hwc-sys (local, in-process): NixOS config + runtime tools
 *   - jt-mcp (stdio backend): JobTread PAVE tools
 *   - n8n-mcp (stdio backend): workflow automation tools
 *
 * Transports:
 *   - stdio  (Claude Code, local)
 *   - Streamable HTTP (Claude.ai, remote — MCP spec 2025-11-25)
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
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";

import { loadConfig } from "./config.js";
import { log, setLogLevel } from "./log.js";
import type { ResourceDef } from "./types.js";
import { ToolRegistry } from "./tools/registry.js";
import { allTools } from "./tools/index.js";
import { allResources } from "./resources/index.js";
import { BackendManager } from "./backend-manager.js";
import { StdioBackend } from "./stdio-backend.js";
import { n8nConsolidation } from "./n8n-consolidation.js";

// ── Helpers ─────────────────────────────────────────────────────────────

function readBody(req: import("node:http").IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString()));
    req.on("error", reject);
  });
}

function isInitializeRequest(body: unknown): boolean {
  if (Array.isArray(body)) {
    return body.some((msg) => msg?.method === "initialize");
  }
  return (body as any)?.method === "initialize";
}

// ── Session tracking ────────────────────────────────────────────────────

interface ManagedSession {
  transport: StreamableHTTPServerTransport;
  server: Server;
  createdAt: number;
  lastActivity: number;
}

const SESSION_TTL_MS = 30 * 60 * 1000; // 30 minutes
const REAPER_INTERVAL_MS = 60 * 1000;  // sweep every minute

// ── Server factory ──────────────────────────────────────────────────────

function createMCPServer(
  backendManager: BackendManager,
  resources: ResourceDef[],
): Server {
  const server = new Server(
    { name: "hwc-sys-mcp", version: "0.3.0" },
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

function buildBackends(): Array<{ backend: StdioBackend; lazy: boolean }> {
  const backends: Array<{ backend: StdioBackend; lazy: boolean }> = [];
  const nodePath = process.env.HWC_NODE_PATH || "node";

  // jt-mcp (JobTread tools) — spawned as stdio child
  const jtSrcDir = process.env.HWC_JT_SRC_DIR;
  if (jtSrcDir) {
    backends.push({
      backend: new StdioBackend({
        name: "jt-mcp",
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
      }),
      lazy: false,
    });
    log.info("Configured jt-mcp backend", { srcDir: jtSrcDir });
  } else {
    log.info("jt-mcp backend skipped (HWC_JT_SRC_DIR not set)");
  }

  // n8n-mcp (workflow automation tools) — spawned as stdio child
  const n8nEntryPoint = process.env.HWC_N8N_ENTRY_POINT;
  if (n8nEntryPoint) {
    backends.push({
      backend: new StdioBackend({
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
      }),
      lazy: false,
    });
    log.info("Configured n8n-mcp backend", { entryPoint: n8nEntryPoint });
  } else {
    log.info("n8n-mcp backend skipped (HWC_N8N_ENTRY_POINT not set)");
  }

  // hwc-crm (front-of-funnel CRM tools) — spawned as a python stdio child.
  // A thin MCP client over the hwc-crm HTTP API (loopback :11660).
  const crmPython = process.env.HWC_CRM_MCP_PYTHON;
  const crmSrcDir = process.env.HWC_CRM_SRC_DIR;
  if (crmPython && crmSrcDir) {
    backends.push({
      backend: new StdioBackend({
        name: "hwc-crm",
        command: crmPython,
        args: ["-m", "hwc_crm.integrations.mcp_server"],
        env: {
          PYTHONPATH: `${crmSrcDir}/src`,
          HWC_CRM_URL: process.env.HWC_CRM_URL || "http://127.0.0.1:11660",
        },
        cwd: crmSrcDir,
      }),
      lazy: false,
    });
    log.info("Configured hwc-crm backend", { srcDir: crmSrcDir });
  } else {
    log.info("hwc-crm backend skipped (HWC_CRM_MCP_PYTHON / HWC_CRM_SRC_DIR not set)");
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
    version: "0.3.0",
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
  for (const { backend } of backends) {
    if (backend.name === "n8n-mcp") {
      manager.addBackend(backend, { consolidate: n8nConsolidation });
    } else {
      manager.addBackend(backend);
    }
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
  // Per-session Server+Transport — claude.ai requires Mcp-Session-Id.
  // Each initialize creates a fresh pair; stale sessions reaped at 30min.
  if (config.transport === "sse" || config.transport === "both") {
    const { createServer } = await import("node:http");
    const port = config.port;
    const host = config.host;

    // Session map: sessionId → { transport, server, timestamps }
    const sessions = new Map<string, ManagedSession>();

    // Legacy SSE transport sessions (protocol version 2024-11-05)
    const sseSessions = new Map<string, SSEServerTransport>();

    // ── Session reaper — sweep stale sessions every minute ──────────
    const reaperInterval = setInterval(() => {
      const now = Date.now();
      for (const [id, session] of sessions) {
        if (now - session.lastActivity > SESSION_TTL_MS) {
          log.info("Reaping stale session", { sessionId: id, ageMin: Math.round((now - session.createdAt) / 60_000) });
          session.transport.close().catch(() => {});
          sessions.delete(id);
        }
      }
    }, REAPER_INTERVAL_MS);
    reaperInterval.unref();

    log.info("Streamable HTTP transport ready (per-session)", {
      sessionTtlMin: SESSION_TTL_MS / 60_000,
      reaperIntervalSec: REAPER_INTERVAL_MS / 1_000,
    });

    const httpServer = createServer(async (req, res) => {
      const startMs = Date.now();
      const url = req.url || "/";
      const method = req.method || "?";

      log.info("HTTP request", {
        method,
        url,
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
          });
        }
      });

      res.on("close", () => {
        if (!res.writableFinished) {
          log.warn("Client disconnected mid-response", {
            method,
            url,
            statusCode: res.statusCode,
            headersSent: res.headersSent,
            durationMs: Date.now() - startMs,
          });
        }
      });

      // CORS
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, HEAD, DELETE, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept, Mcp-Session-Id, Last-Event-ID, Mcp-Protocol-Version");
      res.setHeader("Access-Control-Expose-Headers", "Mcp-Session-Id");

      if (method === "OPTIONS") {
        res.writeHead(204);
        res.end();
        return;
      }

      try {
        await handleRequest(req, res, url, method);
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
          version: "0.3.0",
          tools: allToolsList.length,
          toolsBySource,
          resources: resources.length,
          backends: backendHealth,
          uptime: process.uptime(),
          mode: "per-session",
          activeSessions: sessions.size,
        }));
        return;
      }

      // ── Streamable HTTP (per-session) ─────────────────────────────
      if (url === "/mcp" || url === "/") {
        if (method !== "POST" && method !== "GET" && method !== "DELETE") {
          res.writeHead(405, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Method not allowed" }));
          return;
        }

        const sessionId = req.headers["mcp-session-id"] as string | undefined;

        // Existing session — route to its transport
        if (sessionId && sessions.has(sessionId)) {
          const session = sessions.get(sessionId)!;
          session.lastActivity = Date.now();

          if (method === "DELETE") {
            log.info("Session closed by client", { sessionId });
            await session.transport.handleRequest(req, res);
            session.transport.close().catch(() => {});
            sessions.delete(sessionId);
            return;
          }

          await session.transport.handleRequest(req, res);
          return;
        }

        // Unknown session ID → 404 per MCP spec (client must re-initialize)
        if (sessionId && !sessions.has(sessionId)) {
          res.writeHead(404, { "Content-Type": "application/json" });
          res.end(JSON.stringify({
            jsonrpc: "2.0",
            error: { code: -32000, message: "Session not found. Client should start a new session." },
            id: null,
          }));
          return;
        }

        // No session ID + POST → check if initialize, create new session
        if (method === "POST" && !sessionId) {
          // Read body to check if it's an initialize request (matches datax pattern)
          const body = await readBody(req);
          const parsed = JSON.parse(body);

          if (!isInitializeRequest(parsed)) {
            res.writeHead(400, { "Content-Type": "application/json" });
            res.end(JSON.stringify({
              jsonrpc: "2.0",
              error: { code: -32000, message: "Bad request: missing session ID or not an initialize request" },
              id: null,
            }));
            return;
          }

          const now = Date.now();
          const transport = new StreamableHTTPServerTransport({
            sessionIdGenerator: () => randomUUID(),
            onsessioninitialized: (newSessionId: string) => {
              sessions.set(newSessionId, {
                transport,
                server,
                createdAt: now,
                lastActivity: now,
              });
              log.info("New session initialized", {
                sessionId: newSessionId,
                activeSessions: sessions.size,
              });
            },
          });

          transport.onclose = () => {
            const sid = transport.sessionId;
            if (sid) {
              sessions.delete(sid);
              log.info("Transport closed", { sessionId: sid });
            }
          };

          const server = createMCPServer(manager, resources);
          await server.connect(transport);
          await transport.handleRequest(req, res, parsed);
          return;
        }

        // GET/DELETE without session ID → bad request
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          jsonrpc: "2.0",
          error: { code: -32000, message: "Bad request: missing session ID" },
          id: null,
        }));
        return;
      }

      // ── Legacy SSE transport (protocol version 2024-11-05) ────────
      if (url === "/sse" && method === "GET") {
        log.info("SSE session requested (legacy transport)");
        const sseTransport = new SSEServerTransport("/messages", res);
        const sseServer = createMCPServer(manager, resources);
        sseSessions.set(sseTransport.sessionId, sseTransport);

        res.on("close", () => {
          log.info("SSE session closed", { sessionId: sseTransport.sessionId });
          sseSessions.delete(sseTransport.sessionId);
        });

        await sseServer.connect(sseTransport);
        return;
      }

      if (url?.startsWith("/messages") && method === "POST") {
        const parsedUrl = new URL(url, "http://localhost");
        const sessionId = parsedUrl.searchParams.get("sessionId");
        const sseTransport = sessionId ? sseSessions.get(sessionId) : undefined;

        if (sseTransport) {
          await sseTransport.handlePostMessage(req, res);
        } else {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "No transport found for sessionId" }));
        }
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
        endpoints: ["/mcp", "/sse", "/health"],
      }));
    }

    // Graceful shutdown
    function gracefulShutdown(signal: string) {
      log.info("Shutting down", { signal, activeSessions: sessions.size });
      clearInterval(reaperInterval);
      for (const [id, session] of sessions) {
        session.transport.close().catch(() => {});
        sessions.delete(id);
      }
      for (const [id, sseTransport] of sseSessions) {
        sseTransport.close().catch(() => {});
        sseSessions.delete(id);
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
        legacySse: "/sse",
        health: "/health",
        mode: "per-session",
      });
    });
  }
}

main().catch((error) => {
  log.error("Fatal error", {
    error: error instanceof Error ? error.message : String(error),
  });
  process.exit(1);
});
