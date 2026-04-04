/**
 * StdioBackend — spawns an MCP server as a child process over stdio,
 * discovers its tools, and proxies callTool requests.
 *
 * Handles crash recovery with exponential backoff and a circuit breaker.
 */

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { log } from "./log.js";

export interface StdioBackendConfig {
  name: string;
  command: string;
  args: string[];
  env: Record<string, string>;
  cwd?: string;
  callTimeoutMs?: number; // default 30_000
}

export interface DiscoveredTool {
  name: string;
  description?: string;
  inputSchema: Record<string, unknown>;
}

export type BackendStatus = "starting" | "ready" | "restarting" | "circuit-open" | "stopped";

const MAX_CONSECUTIVE_FAILURES = 5;
const CIRCUIT_BREAKER_WINDOW_MS = 2 * 60 * 1000;
const MAX_BACKOFF_MS = 30_000;

export class StdioBackend {
  readonly name: string;
  private config: StdioBackendConfig;
  private client: Client | null = null;
  private transport: StdioClientTransport | null = null;
  private _status: BackendStatus = "stopped";
  private _tools: DiscoveredTool[] = [];
  private _lastSeen = 0;
  private backoffMs = 1000;
  private failures: number[] = []; // timestamps of recent failures
  private stopping = false;

  get status(): BackendStatus { return this._status; }
  get toolCount(): number { return this._tools.length; }
  get lastSeen(): number { return this._lastSeen; }
  get tools(): DiscoveredTool[] { return this._tools; }

  constructor(config: StdioBackendConfig) {
    this.name = config.name;
    this.config = config;
  }

  async start(): Promise<void> {
    this.stopping = false;
    this._status = "starting";
    await this.spawn();
  }

  async stop(): Promise<void> {
    this.stopping = true;
    this._status = "stopped";
    await this.cleanup();
  }

  async callTool(
    name: string,
    args: Record<string, unknown>,
  ): Promise<{ content: Array<{ type: string; text: string }>; isError?: boolean }> {
    if (this._status === "circuit-open") {
      return {
        content: [{ type: "text", text: JSON.stringify({
          status: "error",
          error_type: "UNAVAILABLE",
          message: `Backend "${this.name}" is unavailable (circuit open after repeated failures)`,
          suggestion: "The backend will auto-recover. Retry in 30 seconds.",
        }) }],
        isError: true,
      };
    }

    if (!this.client || this._status !== "ready") {
      return {
        content: [{ type: "text", text: JSON.stringify({
          status: "error",
          error_type: "UNAVAILABLE",
          message: `Backend "${this.name}" is ${this._status}`,
          suggestion: "Wait for the backend to finish starting.",
        }) }],
        isError: true,
      };
    }

    const timeout = this.config.callTimeoutMs ?? 30_000;
    try {
      const result = await Promise.race([
        this.client.callTool({ name, arguments: args }),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error(`Tool call timed out after ${timeout}ms`)), timeout),
        ),
      ]);
      this._lastSeen = Date.now();
      return result as { content: Array<{ type: string; text: string }>; isError?: boolean };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        content: [{ type: "text", text: JSON.stringify({
          status: "error",
          error_type: message.includes("timed out") ? "TIMEOUT" : "INTERNAL_ERROR",
          message,
          suggestion: "Check backend logs for details.",
          context: { backend: this.name, tool: name },
        }) }],
        isError: true,
      };
    }
  }

  private async spawn(): Promise<void> {
    await this.cleanup();

    log.info(`Spawning stdio backend: ${this.name}`, {
      command: this.config.command,
      args: this.config.args,
      cwd: this.config.cwd,
    });

    try {
      this.transport = new StdioClientTransport({
        command: this.config.command,
        args: this.config.args,
        env: { ...this.config.env, PATH: process.env.PATH || "" },
        cwd: this.config.cwd,
      });

      this.transport.onclose = () => {
        if (!this.stopping) {
          log.warn(`Backend "${this.name}" transport closed unexpectedly`);
          this.scheduleRestart();
        }
      };

      this.transport.onerror = (err) => {
        log.error(`Backend "${this.name}" transport error`, { error: err.message });
      };

      this.client = new Client(
        { name: `hwc-gateway/${this.name}`, version: "0.2.0" },
        { capabilities: {} },
      );

      await this.client.connect(this.transport);

      // Discover tools
      const response = await this.client.listTools();
      this._tools = (response.tools || []).map((t) => ({
        name: t.name,
        description: t.description,
        inputSchema: t.inputSchema as Record<string, unknown>,
      }));

      this._status = "ready";
      this._lastSeen = Date.now();
      this.backoffMs = 1000; // reset backoff on success
      log.info(`Backend "${this.name}" ready`, { tools: this._tools.length });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      log.error(`Backend "${this.name}" failed to start`, { error: message });
      this.recordFailure();
      if (this._status !== "circuit-open") {
        this.scheduleRestart();
      }
    }
  }

  private async cleanup(): Promise<void> {
    try { if (this.transport) await this.transport.close(); } catch { /* ignore */ }
    try { if (this.client) await this.client.close(); } catch { /* ignore */ }
    this.client = null;
    this.transport = null;
  }

  private recordFailure(): void {
    const now = Date.now();
    this.failures.push(now);
    // Prune old failures outside the window
    this.failures = this.failures.filter((t) => now - t < CIRCUIT_BREAKER_WINDOW_MS);
    if (this.failures.length >= MAX_CONSECUTIVE_FAILURES) {
      log.error(`Backend "${this.name}" circuit breaker OPEN — ${this.failures.length} failures in ${CIRCUIT_BREAKER_WINDOW_MS / 1000}s`);
      this._status = "circuit-open";
      // Attempt recovery after max backoff
      setTimeout(() => {
        if (this._status === "circuit-open" && !this.stopping) {
          log.info(`Backend "${this.name}" circuit breaker — attempting recovery`);
          this.failures = [];
          this.spawn();
        }
      }, MAX_BACKOFF_MS);
    }
  }

  private scheduleRestart(): void {
    if (this.stopping) return;
    this._status = "restarting";
    log.info(`Backend "${this.name}" restarting in ${this.backoffMs}ms`);
    setTimeout(() => {
      if (!this.stopping) this.spawn();
    }, this.backoffMs);
    this.backoffMs = Math.min(this.backoffMs * 2, MAX_BACKOFF_MS);
  }
}
