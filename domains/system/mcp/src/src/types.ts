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
}

/** Tool definition matching the heartwood-mcp pattern */
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
