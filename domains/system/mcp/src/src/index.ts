/**
 * HWC Infrastructure MCP Server — entry point.
 *
 * Exposes NixOS system configuration and runtime state as MCP tools.
 * Supports dual transport: stdio (Claude Code) + SSE (Claude.ai mobile).
 *
 * Phase 1: services status, git status, health check
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";

import { loadConfig } from "./config.js";
import { log, setLogLevel } from "./log.js";
import { ToolRegistry } from "./tools/registry.js";
import { allTools } from "./tools/index.js";
import { allResources } from "./resources/index.js";

async function main() {
  const config = loadConfig();
  setLogLevel(config.logLevel);

  log.info("Starting HWC Infrastructure MCP Server", {
    transport: config.transport,
    logLevel: config.logLevel,
    hostname: config.hostname,
  });

  // ── Build tool registry ─────────────────────────────────────────────
  const registry = new ToolRegistry();
  registry.register(allTools(config));
  log.info("Tool registry loaded", { toolCount: registry.count() });

  // ── Load resources ──────────────────────────────────────────────────
  const resources = allResources(config.nixosConfigPath);
  log.info("Resources loaded", { resourceCount: resources.length });

  // ── Create MCP server (low-level for raw JSON schema support) ───────
  const server = new Server(
    { name: "hwc-infra-mcp", version: "0.1.0" },
    { capabilities: { tools: {}, resources: {} } }
  );

  // ── Tool handlers ───────────────────────────────────────────────────
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
        content: [
          {
            type: "text",
            text: JSON.stringify(result, null, 2),
          },
        ],
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
          {
            type: "text",
            text: JSON.stringify({ status: "error", message, error: "INTERNAL_ERROR" }),
          },
        ],
        isError: true,
      };
    }
  });

  // ── Resource handlers ───────────────────────────────────────────────
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
        {
          uri: resource.uri,
          mimeType: resource.mimeType,
          text: content,
        },
      ],
    };
  });

  // ── Start transport ─────────────────────────────────────────────────
  if (config.transport === "stdio" || config.transport === "both") {
    if (config.transport === "stdio") {
      const transport = new StdioServerTransport();
      await server.connect(transport);
      log.info("HWC Infra MCP Server running on stdio");
    }
  }

  if (config.transport === "sse" || config.transport === "both") {
    const { createServer } = await import("node:http");
    const port = config.port;
    const host = config.host;

    let activeTransport: SSEServerTransport | null = null;

    const httpServer = createServer(async (req, res) => {
      // CORS headers for browser-based MCP clients
      res.setHeader("Access-Control-Allow-Origin", "*");
      res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type");

      if (req.method === "OPTIONS") {
        res.writeHead(204);
        res.end();
        return;
      }

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
        await activeTransport.handlePostMessage(req, res);
      } else if (req.method === "GET" && req.url === "/health") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({
            status: "ok",
            server: "hwc-infra-mcp",
            version: "0.1.0",
            tools: registry.count(),
            resources: resources.length,
            uptime: process.uptime(),
          })
        );
      } else {
        res.writeHead(404, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Not found", endpoints: ["/sse", "/messages", "/health"] }));
      }
    });

    httpServer.listen(port, host, () => {
      log.info(`HWC Infra MCP SSE server listening on ${host}:${port}`);
    });
  }
}

main().catch((error) => {
  log.error("Fatal error", {
    error: error instanceof Error ? error.message : String(error),
  });
  process.exit(1);
});
