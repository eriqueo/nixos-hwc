/**
 * Shared TypeScript types for the HWC Infrastructure MCP Server.
 */

/** Standard result wrapper for all tool responses */
export interface ToolResult<T = unknown> {
  status: "ok" | "error" | "partial";
  message: string;
  data?: T;
  error?: string;
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
}

/** MCP Resource definition */
export interface ResourceDef {
  uri: string;
  name: string;
  description: string;
  mimeType: string;
  load: () => Promise<string>;
}
