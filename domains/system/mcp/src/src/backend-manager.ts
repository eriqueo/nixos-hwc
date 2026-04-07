/**
 * BackendManager — aggregates tools from in-process hwc-sys tools and
 * stdio backends (heartwood-mcp, n8n-mcp) into a unified tool namespace.
 *
 * Routes callTool requests to the correct backend by tool name.
 * Detects name collisions at startup.
 */

import { log } from "./log.js";
import type { ToolDef } from "./types.js";
import { StdioBackend, type BackendStatus } from "./stdio-backend.js";
import { transformN8nResponse } from "./transforms/n8n.js";

interface AggregatedTool {
  name: string;
  description?: string;
  inputSchema: Record<string, unknown>;
  source: string; // "local" or backend name
}

export class BackendManager {
  private localTools: ToolDef[] = [];
  private backends: StdioBackend[] = [];
  private toolMap = new Map<string, { source: string; backend?: StdioBackend; local?: ToolDef }>();

  registerLocal(tools: ToolDef[]): void {
    this.localTools = tools;
  }

  addBackend(backend: StdioBackend): void {
    this.backends.push(backend);
  }

  async startAll(): Promise<void> {
    // Start all backends concurrently — failures are non-fatal (partial startup)
    const results = await Promise.allSettled(
      this.backends.map((b) => b.start()),
    );

    for (let i = 0; i < results.length; i++) {
      if (results[i].status === "rejected") {
        const err = (results[i] as PromiseRejectedResult).reason;
        log.error(`Backend "${this.backends[i].name}" failed to start — continuing without it`, {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    // Build tool map and check for collisions
    this.rebuildToolMap();

    // Log summary
    const localCount = this.localTools.length;
    const backendSummary = this.backends.map((b) => `${b.name}: ${b.toolCount}`).join(", ");
    const total = this.toolMap.size;
    log.info(`Gateway ready: ${total} tools (hwc-sys: ${localCount}, ${backendSummary})`);
  }

  private rebuildToolMap(): void {
    this.toolMap.clear();

    // Register local tools
    for (const tool of this.localTools) {
      this.toolMap.set(tool.name, { source: "hwc-sys", local: tool });
    }

    // Register backend tools — check for collisions
    for (const backend of this.backends) {
      if (backend.status !== "ready") continue;
      for (const tool of backend.tools) {
        const existing = this.toolMap.get(tool.name);
        if (existing) {
          // Hard failure — tool name collision
          throw new Error(
            `Tool name collision: "${tool.name}" exists in both "${existing.source}" and "${backend.name}". ` +
            `Rename one of them to resolve.`,
          );
        }
        this.toolMap.set(tool.name, { source: backend.name, backend });
      }
    }
  }

  allTools(): AggregatedTool[] {
    const tools: AggregatedTool[] = [];

    for (const t of this.localTools) {
      tools.push({
        name: t.name,
        description: t.description,
        inputSchema: t.inputSchema,
        source: "hwc-sys",
      });
    }

    for (const backend of this.backends) {
      if (backend.status !== "ready" && backend.status !== "restarting") continue;
      for (const t of backend.tools) {
        tools.push({
          name: t.name,
          description: t.description,
          inputSchema: t.inputSchema,
          source: backend.name,
        });
      }
    }

    return tools;
  }

  async callTool(
    name: string,
    args: Record<string, unknown>,
  ): Promise<{ content: Array<{ type: string; text: string }>; isError?: boolean }> {
    const entry = this.toolMap.get(name);

    if (!entry) {
      return {
        content: [{ type: "text", text: JSON.stringify({
          status: "error",
          error_type: "NOT_FOUND",
          message: `Unknown tool: ${name}`,
          suggestion: "Use tools/list to see available tools.",
        }) }],
        isError: true,
      };
    }

    // Local tool
    if (entry.local) {
      const startMs = Date.now();
      try {
        const result = await entry.local.handler(args);
        log.debug("Local tool call completed", { tool: name, status: result.status, durationMs: Date.now() - startMs });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          isError: result.status === "error",
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        log.error("Local tool threw exception", { tool: name, error: message, durationMs: Date.now() - startMs });
        return {
          content: [{ type: "text", text: JSON.stringify({
            status: "error",
            message,
            error_type: "INTERNAL_ERROR",
            suggestion: "This is an unhandled exception. Check server logs.",
          }) }],
          isError: true,
        };
      }
    }

    // Backend tool
    if (entry.backend) {
      const result = await entry.backend.callTool(name, args);

      // Apply n8n response transforms
      if (name.startsWith("n8n_") || name === "validate_workflow" || name === "validate_node") {
        try {
          for (const item of result.content) {
            if (item.type === "text" && item.text) {
              const parsed = JSON.parse(item.text);
              item.text = JSON.stringify(transformN8nResponse(name, parsed), null, 2);
            }
          }
        } catch {
          // Transform failed — return original response unchanged
        }
      }

      return result;
    }

    return {
      content: [{ type: "text", text: `Internal error: no handler for tool "${name}"` }],
      isError: true,
    };
  }

  healthReport(): Record<string, { status: BackendStatus; toolCount: number; lastSeen: number }> {
    const report: Record<string, { status: BackendStatus; toolCount: number; lastSeen: number }> = {};
    for (const backend of this.backends) {
      report[backend.name] = {
        status: backend.status,
        toolCount: backend.toolCount,
        lastSeen: backend.lastSeen,
      };
    }
    return report;
  }

  async stopAll(): Promise<void> {
    await Promise.allSettled(this.backends.map((b) => b.stop()));
  }
}
