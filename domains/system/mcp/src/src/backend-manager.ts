/**
 * BackendManager — aggregates tools from in-process hwc-sys tools and
 * stdio backends (heartwood-mcp, n8n-mcp) into a unified tool namespace.
 *
 * Routes callTool requests to the correct backend by tool name.
 * Detects name collisions at startup.
 *
 * Lazy loading: backends can be marked as "lazy". Their tools are hidden
 * from ListTools until a connect meta-tool is called. This reduces token
 * overhead for Claude.ai sessions that don't need all backends.
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

  /** Backends marked lazy start hidden — their tools only appear after connect. */
  private lazyBackends = new Set<string>();
  /** Activated backends have been "connected" — their tools appear in allTools(). */
  private activatedBackends = new Set<string>();

  registerLocal(tools: ToolDef[]): void {
    this.localTools = tools;
  }

  addBackend(backend: StdioBackend, options?: { lazy?: boolean }): void {
    this.backends.push(backend);
    if (options?.lazy) {
      this.lazyBackends.add(backend.name);
    }
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
    const backendSummary = this.backends.map((b) => {
      const lazy = this.lazyBackends.has(b.name) ? " (lazy)" : "";
      return `${b.name}: ${b.toolCount}${lazy}`;
    }).join(", ");
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

    // Register connect meta-tools for lazy backends
    for (const backend of this.backends) {
      if (!this.lazyBackends.has(backend.name)) continue;
      if (backend.status !== "ready") continue;
      const metaName = `hwc_connect_${backend.name.replace(/-/g, "_")}`;
      this.toolMap.set(metaName, {
        source: "hwc-sys",
        local: {
          name: metaName,
          description: `Activate ${backend.name} tools (${backend.toolCount} tools). ` +
            `Call this first to access ${backend.name} capabilities.`,
          inputSchema: { type: "object", properties: {} },
          handler: async () => this.activateBackend(backend.name),
        },
      });
    }
  }

  /**
   * Activate a lazy backend — its tools will appear in allTools() after this.
   * Returns a summary of the activated tools.
   */
  private async activateBackend(backendName: string): Promise<{
    status: "ok" | "error" | "partial";
    message: string;
    data?: unknown;
  }> {
    const backend = this.backends.find((b) => b.name === backendName);
    if (!backend) {
      return { status: "error", message: `Backend not found: ${backendName}` };
    }
    if (backend.status !== "ready") {
      return { status: "error", message: `Backend ${backendName} is not ready (status: ${backend.status})` };
    }

    this.activatedBackends.add(backendName);
    log.info(`Backend "${backendName}" activated — ${backend.toolCount} tools now visible`);

    // Return tool catalog so Claude knows what's available without another ListTools round-trip
    const toolSummary = backend.tools.map((t) => ({
      name: t.name,
      description: t.description,
    }));

    return {
      status: "ok",
      message: `Activated ${backend.toolCount} ${backendName} tools. They are now available for use.`,
      data: { tools: toolSummary },
    };
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

      const isLazy = this.lazyBackends.has(backend.name);
      const isActivated = this.activatedBackends.has(backend.name);

      if (isLazy && !isActivated) {
        // Lazy and not activated: only show the connect meta-tool
        const metaName = `hwc_connect_${backend.name.replace(/-/g, "_")}`;
        const metaEntry = this.toolMap.get(metaName);
        if (metaEntry?.local) {
          tools.push({
            name: metaEntry.local.name,
            description: metaEntry.local.description,
            inputSchema: metaEntry.local.inputSchema,
            source: "hwc-sys",
          });
        }
        continue;
      }

      // Non-lazy or activated: include all tools
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

    // Local tool (including connect meta-tools)
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

    // Backend tool — works even if backend is lazy (tools are in toolMap from startup)
    if (entry.backend) {
      // Auto-activate lazy backends on first tool call
      if (this.lazyBackends.has(entry.backend.name) && !this.activatedBackends.has(entry.backend.name)) {
        this.activatedBackends.add(entry.backend.name);
        log.info(`Backend "${entry.backend.name}" auto-activated via direct tool call: ${name}`);
      }

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

  healthReport(): Record<string, { status: BackendStatus; toolCount: number; lastSeen: number; lazy?: boolean; activated?: boolean }> {
    const report: Record<string, { status: BackendStatus; toolCount: number; lastSeen: number; lazy?: boolean; activated?: boolean }> = {};
    for (const backend of this.backends) {
      report[backend.name] = {
        status: backend.status,
        toolCount: backend.toolCount,
        lastSeen: backend.lastSeen,
        ...(this.lazyBackends.has(backend.name) ? {
          lazy: true,
          activated: this.activatedBackends.has(backend.name),
        } : {}),
      };
    }
    return report;
  }

  async stopAll(): Promise<void> {
    await Promise.allSettled(this.backends.map((b) => b.stop()));
  }
}
