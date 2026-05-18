/**
 * BackendManager — aggregates tools from in-process hwc-sys tools and
 * stdio backends (jt-mcp, n8n-mcp) into a unified tool namespace.
 *
 * Routes callTool requests to the correct backend by tool name.
 * Detects name collisions at startup.
 *
 * Supports optional consolidation functions per backend: a ConsolidateFn
 * receives the discovered tools + a call proxy, returns a set of new
 * consolidated ToolDef[] and a list of original tool names to hide.
 */

import { log } from "./log.js";
import type { ToolDef } from "./types.js";
import { StdioBackend, type BackendStatus, type DiscoveredTool } from "./stdio-backend.js";
import { transformN8nResponse } from "./transforms/n8n.js";

interface AggregatedTool {
  name: string;
  description?: string;
  inputSchema: Record<string, unknown>;
  source: string; // "local" or backend name
}

/** Call proxy handed to consolidation functions */
export type BackendCallFn = (
  name: string,
  args: Record<string, unknown>,
) => Promise<{ content: Array<{ type: string; text: string }>; isError?: boolean }>;

/** Result returned by a consolidation function */
export interface ConsolidationResult {
  /** New consolidated tools to expose in place of (some) backend tools */
  tools: ToolDef[];
  /** Original backend tool names to hide from the tool list */
  hidden: string[];
}

/** Function that consolidates raw backend tools into fewer wrapped tools */
export type ConsolidateFn = (
  tools: DiscoveredTool[],
  call: BackendCallFn,
) => ConsolidationResult;

/**
 * Parse a raw MCP content response from a backend tool call into a
 * structured result. Used inside consolidation handlers.
 */
export function parseBackendResult(r: {
  content: Array<{ type: string; text: string }>;
  isError?: boolean;
}): { status: "ok" | "error"; data?: unknown; message?: string } {
  const text = r.content[0]?.text ?? "";
  try {
    const parsed = JSON.parse(text) as Record<string, unknown>;
    return r.isError
      ? { status: "error", message: String(parsed?.error ?? parsed?.message ?? text) }
      : { status: "ok", data: parsed };
  } catch {
    return r.isError ? { status: "error", message: text } : { status: "ok", data: text };
  }
}

export class BackendManager {
  private localTools: ToolDef[] = [];
  private backends: StdioBackend[] = [];
  private toolMap = new Map<string, { source: string; backend?: StdioBackend; local?: ToolDef }>();

  /** Consolidation functions keyed by backend name */
  private consolidationFns = new Map<string, ConsolidateFn>();
  /** Consolidated tool lists keyed by backend name */
  private consolidatedTools = new Map<string, ConsolidationResult>();

  registerLocal(tools: ToolDef[]): void {
    this.localTools = tools;
  }

  addBackend(backend: StdioBackend, options?: { consolidate?: ConsolidateFn }): void {
    this.backends.push(backend);
    if (options?.consolidate) {
      this.consolidationFns.set(backend.name, options.consolidate);
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

    // Build consolidated tools for backends that have a consolidation fn
    for (const backend of this.backends) {
      const consolidate = this.consolidationFns.get(backend.name);
      if (consolidate && backend.status === "ready") {
        const callFn: BackendCallFn = (name, args) => backend.callTool(name, args);
        const result = consolidate(backend.tools, callFn);
        this.consolidatedTools.set(backend.name, result);
        log.info(
          `Backend "${backend.name}" consolidated: ${backend.toolCount} raw → ${result.tools.length} consolidated (${result.hidden.length} hidden)`,
        );
      }
    }

    // Build tool map and check for collisions
    this.rebuildToolMap();

    // Log summary
    const localCount = this.localTools.length;
    const backendSummary = this.backends.map((b) => {
      const cons = this.consolidatedTools.get(b.name);
      if (cons) {
        const passThrough = b.toolCount - cons.hidden.length;
        return `${b.name}: ${cons.tools.length} consolidated + ${passThrough} pass-through`;
      }
      return `${b.name}: ${b.toolCount}`;
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

    // Register consolidated tools as local entries (they have handler functions)
    for (const [backendName, result] of this.consolidatedTools) {
      for (const tool of result.tools) {
        const existing = this.toolMap.get(tool.name);
        if (existing) {
          throw new Error(
            `Tool name collision: "${tool.name}" exists in both "${existing.source}" and "${backendName}" (consolidated). ` +
            `Rename one of them to resolve.`,
          );
        }
        this.toolMap.set(tool.name, { source: backendName, local: tool });
      }
    }

    // Register backend tools — check for collisions, skip hidden tools
    for (const backend of this.backends) {
      if (backend.status !== "ready") continue;
      const consolidation = this.consolidatedTools.get(backend.name);
      const hiddenSet = consolidation ? new Set(consolidation.hidden) : null;

      for (const tool of backend.tools) {
        // Skip tools hidden by consolidation
        if (hiddenSet && hiddenSet.has(tool.name)) continue;

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

    // Consolidated tools (exposed as local entries)
    for (const [backendName, result] of this.consolidatedTools) {
      for (const t of result.tools) {
        tools.push({
          name: t.name,
          description: t.description,
          inputSchema: t.inputSchema,
          source: backendName,
        });
      }
    }

    for (const backend of this.backends) {
      if (backend.status !== "ready" && backend.status !== "restarting") continue;
      const consolidation = this.consolidatedTools.get(backend.name);
      const hiddenSet = consolidation ? new Set(consolidation.hidden) : null;

      for (const t of backend.tools) {
        // Skip tools hidden by consolidation
        if (hiddenSet && hiddenSet.has(t.name)) continue;

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

    // Local tool (including consolidated tools and connect meta-tools)
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

    if (entry.backend) {
      const result = await entry.backend.callTool(name, args);

      // Apply n8n response transforms
      if (name.startsWith("n8n_") || name === "validate_workflow" || name === "validate_node" || name === "search_nodes" || name === "search_templates") {
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
