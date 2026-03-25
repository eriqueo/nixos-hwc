/**
 * Heartwood MCP Server — unified interface to all business systems.
 *
 * Phase 1: JobTread (63 tools via PAVE API)
 * Phase 2: Paperless-ngx, Firefly III
 * Phase 3: Compound operations (n8n-backed)
 * Phase 4: Query & intelligence tools (Postgres views)
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
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

  // ── Create MCP server ───────────────────────────────────────────────
  const server = new McpServer({
    name: "heartwood-mcp",
    version: "0.1.0",
  });

  // Register all tools with the MCP server
  for (const tool of registry.getAll()) {
    // Use the raw tool registration approach for dynamic tools
    server.tool(
      tool.name,
      tool.description,
      tool.inputSchema.properties,
      async (params: Record<string, unknown>) => {
        const startMs = Date.now();
        try {
          const result = await tool.handler(params);
          const durationMs = Date.now() - startMs;

          log.debug("Tool call completed", {
            tool: tool.name,
            success: result.success,
            durationMs,
          });

          if (result.success) {
            return {
              content: [
                {
                  type: "text" as const,
                  text: JSON.stringify(result.data, null, 2),
                },
              ],
            };
          } else {
            return {
              content: [
                {
                  type: "text" as const,
                  text: JSON.stringify(
                    {
                      error: result.error,
                      code: result.code,
                      details: result.details,
                    },
                    null,
                    2
                  ),
                },
              ],
              isError: true,
            };
          }
        } catch (error) {
          const durationMs = Date.now() - startMs;
          const message =
            error instanceof Error ? error.message : String(error);
          log.error("Tool call threw exception", {
            tool: tool.name,
            error: message,
            durationMs,
          });
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify({
                  error: message,
                  code: "INTERNAL_ERROR",
                }),
              },
            ],
            isError: true,
          };
        }
      }
    );
  }

  // ── Start transport ─────────────────────────────────────────────────
  if (config.transport === "stdio") {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    log.info("Heartwood MCP Server running on stdio");
  } else {
    // SSE transport for remote access (Claude chat, n8n)
    log.info("SSE transport configured", {
      host: config.sse.host,
      port: config.sse.port,
    });
    // SSE transport requires an HTTP server — using the SDK's built-in support
    // For production, this would be behind Caddy reverse proxy
    const { createServer } = await import("http");
    const httpServer = createServer(async (req, res) => {
      if (req.method === "GET" && req.url === "/sse") {
        const transport = new SSEServerTransport("/messages", res);
        await server.connect(transport);
      } else if (req.method === "POST" && req.url === "/messages") {
        // Handle incoming messages for SSE transport
        let body = "";
        req.on("data", (chunk: Buffer) => {
          body += chunk.toString();
        });
        req.on("end", () => {
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ received: true }));
        });
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
