/**
 * Shared TypeScript types for the HWC Infrastructure MCP Server.
 */

/** Categorised error types for structured MCP error responses. */
export type McpErrorType =
  | "NOT_FOUND"        // service, file, resource, binary
  | "PERMISSION_DENIED"// sandbox / filesystem permission
  | "VALIDATION_ERROR" // bad input parameters
  | "TIMEOUT"          // operation exceeded time limit
  | "COMMAND_FAILED"   // shell command returned non-zero
  | "NETWORK_ERROR"    // HTTP fetch / API unreachable
  | "UNAVAILABLE"      // service or endpoint not running
  | "INTERNAL_ERROR";  // unexpected exception

/**
 * Universal Result Contract — a self-describing, render-ready view of a tool's
 * payload. Emitted as MCP `structuredContent` (in addition to the legacy text
 * block) so any consumer — the workbench TUI tiles, the web Portal — renders it
 * with zero per-tool adapter. `kind` picks the renderer; `data` carries that
 * kind's canonical fields; producer noise (status/message/etc.) lives in `meta`.
 * Spec: brain note universal_result_contract_schema.
 */
export type ViewKind = "text" | "list" | "table" | "kanban" | "metric" | "status";

export interface ResultEnvelope<T = unknown> {
  kind: ViewKind;
  title?: string;
  data: T;
  meta?: Record<string, unknown>;
}

/** Standard result wrapper for all tool responses */
export interface ToolResult<T = unknown> {
  status: "ok" | "error" | "partial";
  message: string;
  data?: T;
  error?: string;
  /** Structured error fields — present when status is "error" */
  error_type?: McpErrorType;
  suggestion?: string;
  context?: Record<string, unknown>;
  /**
   * Optional Universal Result Contract view. When present, backend-manager
   * emits it as `structuredContent` alongside the legacy text block — the
   * dual-emit path (legacy readers unaffected; contract-aware consumers prefer
   * structuredContent). Tools that feed a dashboard tile set this.
   */
  view?: ResultEnvelope;
}

/** Tool definition matching the jt-mcp pattern */
export interface ToolDef {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  handler: (args: Record<string, unknown>) => Promise<ToolResult>;
}

/** Result of a shell command execution */
export interface ExecResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Systemd service status */
export interface ServiceStatus {
  name: string;
  activeState: string;
  subState: string;
  description: string;
  uptime?: string;
  memoryUsage?: string;
  mainPid?: number;
  restartCount?: number;
  type: "container" | "native";
}

/** Container stats from podman */
export interface ContainerStats {
  name: string;
  id: string;
  cpu: string;
  memory: string;
  memLimit: string;
  netIO: string;
  blockIO: string;
  pids: number;
  status: string;
}

/** Server configuration loaded from environment */
export interface ServerConfig {
  port: number;
  host: string;
  transport: "stdio" | "sse" | "both";
  logLevel: "debug" | "info" | "warn" | "error";
  nixosConfigPath: string;
  cacheTtl: {
    runtime: number;
    declarative: number;
  };
  mutations: {
    enabled: boolean;
    allowedActions: string[];
  };
  workspace: string;
  hostname: string;
  cmsAppPath: string;
}

/** MCP Resource definition */
export interface ResourceDef {
  uri: string;
  name: string;
  description: string;
  mimeType: string;
  load: () => Promise<string>;
}
