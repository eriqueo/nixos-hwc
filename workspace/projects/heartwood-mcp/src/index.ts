/**
 * Heartwood MCP Server — unified interface to all business systems.
 *
 * Phase 1: JobTread (63 tools via PAVE API)
 * Phase 2: Paperless-ngx, Firefly III
 * Phase 3: Compound operations (n8n-backed)
 * Phase 4: Query & intelligence tools (Postgres views)
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";
import { loadConfig } from "./config.js";
import { log, setLogLevel } from "./logging/logger.js";
import { PaveClient } from "./pave/index.js";
import { ToolRegistry } from "./tools/registry.js";
import { allJtTools } from "./tools/jt/index.js";

async function main(): Promise<void> {
  const config = loadConfig();
  setLogLevel(config.logLevel);

  log.info("Starting Heartwood MCP Server", {
    transport: config.transport,
    logLevel: config.logLevel,
  });

  // ── Initialize PAVE client ──────────────────────────────────────────
  const pave = new PaveClient(config.jt);

  // ── Build tool registry ─────────────────────────────────────────────
  const registry = new ToolRegistry();
  registry.register(allJtTools(pave));

  log.info("Tool registry loaded", { toolCount: registry.count() });

  // ── Create MCP server (low-level for raw JSON schema support) ───────
  const server = new Server(
    { name: "heartwood-mcp", version: "0.1.0" },
    { capabilities: { tools: {} } }
  );

  // Build tool list for ListTools handler
  const allTools = registry.getAll();

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: allTools.map((t) => ({
      name: t.name,
      description: t.description,
      inputSchema: t.inputSchema,
    })),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const toolName = request.params.name;
    const toolArgs = (request.params.arguments ?? {}) as Record<string, unknown>;
    const tool = allTools.find((t) => t.name === toolName);

    if (!tool) {
      return {
        content: [{ type: "text" as const, text: `Unknown tool: ${toolName}` }],
        isError: true,
      };
    }

    const startMs = Date.now();
    try {
      const result = await tool.handler(toolArgs);
      const durationMs = Date.now() - startMs;
      log.debug("Tool call completed", { tool: toolName, success: result.success, durationMs });

      if (result.success) {
        return {
          content: [{ type: "text" as const, text: JSON.stringify(result.data, null, 2) }],
        };
      } else {
        return {
          content: [{
            type: "text" as const,
            text: JSON.stringify({ error: result.error, code: result.code, details: result.details }, null, 2),
          }],
          isError: true,
        };
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      log.error("Tool call threw exception", { tool: toolName, error: message, durationMs: Date.now() - startMs });
      return {
        content: [{ type: "text" as const, text: JSON.stringify({ error: message, code: "INTERNAL_ERROR" }) }],
        isError: true,
      };
    }
  });

  // ── Start transport ─────────────────────────────────────────────────
  if (config.transport === "stdio") {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    log.info("Heartwood MCP Server running on stdio");
  } else {
    // SSE transport for remote access (Claude chat, n8n)
    // Behind Caddy reverse proxy in production
    log.info("SSE transport configured", {
      host: config.sse.host,
      port: config.sse.port,
    });
    const { createServer } = await import("http");

    // Track the active SSE transport so POST /messages can route to it
    let activeTransport: SSEServerTransport | null = null;

    const httpServer = createServer(async (req, res) => {
      if (req.method === "GET" && req.url === "/sse") {
        const transport = new SSEServerTransport("/messages", res);
        activeTransport = transport;
        await server.connect(transport);
      } else if (req.method === "POST" && req.url?.startsWith("/messages")) {
        if (!activeTransport) {
          res.writeHead(503, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "No active SSE connection" }));
          return;
        }
        // Route the message through the SSE transport for bidirectional communication
        await activeTransport.handlePostMessage(req, res);
      } else {
        res.writeHead(404);
        res.end("Not found");
      }
    });
    httpServer.listen(config.sse.port, config.sse.host, () => {
      log.info(
        `Heartwood MCP Server listening on ${config.sse.host}:${config.sse.port}`
      );
    });
  }
}

main().catch((error) => {
  log.error("Fatal error", {
    error: error instanceof Error ? error.message : String(error),
  });
  process.exit(1);
});
