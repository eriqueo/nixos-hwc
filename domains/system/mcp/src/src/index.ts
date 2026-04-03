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
    { name: "hwc-infra-mcp", version: "0.1.0" },
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
    const sessions = new Map<string, {
      server: Server;
      transport: StreamableHTTPServerTransport;
    }>();

    // Legacy SSE (single active connection)
    let legacySseTransport: SSEServerTransport | null = null;
    let legacySseServer: Server | null = null;

    const httpServer = createServer(async (req, res) => {
      // CORS — required for browser-based MCP clients (Claude.ai)
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, HEAD, DELETE, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type, Accept, Mcp-Session-Id, Last-Event-ID");
      res.setHeader("Access-Control-Expose-Headers", "Mcp-Session-Id");

      if (req.method === "OPTIONS") {
        res.writeHead(204);
        res.end();
        return;
      }

      const url = req.url || "/";

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
          method: req.method,
          headers: {
            ...req.headers,
            host: `127.0.0.1:${n8nPort}`,
            authorization: `Bearer ${n8nAuthToken}`,
          },
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

        req.pipe(proxyReq);
        return;
      }

      // ── Health check ────────────────────────────────────────────────
      if (url === "/health" && req.method === "GET") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({
          status: "ok",
          server: "hwc-infra-mcp",
          version: "0.1.0",
          tools: registry.count(),
          resources: resources.length,
          uptime: process.uptime(),
          activeSessions: sessions.size,
        }));
        return;
      }

      // ── Streamable HTTP (MCP spec 2025-06-18) ───────────────────────
      // Handles POST (JSON-RPC), GET (SSE stream), DELETE (session close)
      if (url === "/mcp" || url === "/") {
        const sessionId = req.headers["mcp-session-id"] as string | undefined;

        // Route to existing session
        if (sessionId && sessions.has(sessionId)) {
          const session = sessions.get(sessionId)!;
          await session.transport.handleRequest(req, res);
          return;
        }

        // New session — must be a POST with initialize
        if (req.method === "POST") {
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
            onsessioninitialized: (sessionId) => {
              sessions.set(sessionId, { server, transport });
              log.info("Streamable HTTP session created", { sessionId });

              transport.onclose = () => {
                sessions.delete(sessionId);
                log.info("Streamable HTTP session closed", { sessionId });
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
        if (req.method === "GET" && !sessionId) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Session ID required for GET SSE stream" }));
          return;
        }

        // Unknown session
        if (sessionId) {
          res.writeHead(404, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "Session not found" }));
          return;
        }

        res.writeHead(405, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Method not allowed" }));
        return;
      }

      // ── Legacy SSE (for older clients) ──────────────────────────────
      if (url === "/sse" && req.method === "GET") {
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

      if (url?.startsWith("/messages") && req.method === "POST") {
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
        endpoints: ["/mcp", "/sse", "/messages", "/health"],
      }));
    });

    httpServer.listen(port, host, () => {
      log.info(`HWC Infra MCP server listening on ${host}:${port}`, {
        streamableHttp: "/mcp",
        legacySse: "/sse",
        health: "/health",
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
