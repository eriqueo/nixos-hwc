/**
 * Configuration loader — reads from environment variables set by the NixOS module.
 */

import type { ServerConfig } from "./types.js";

export function loadConfig(): ServerConfig {
  return {
    port: parseInt(process.env.HWC_MCP_PORT || "6200", 10),
    host: process.env.HWC_MCP_HOST || "127.0.0.1",
    transport: (process.env.HWC_MCP_TRANSPORT as ServerConfig["transport"]) || "stdio",
    logLevel: (process.env.HWC_MCP_LOG_LEVEL as ServerConfig["logLevel"]) || "info",
    nixosConfigPath: process.env.HWC_NIXOS_CONFIG_PATH || "/home/eric/.nixos",
    cacheTtl: {
      runtime: parseInt(process.env.HWC_MCP_CACHE_TTL_RUNTIME || "60", 10),
      declarative: parseInt(process.env.HWC_MCP_CACHE_TTL_DECLARATIVE || "300", 10),
    },
    mutations: {
      enabled: process.env.HWC_MCP_MUTATIONS_ENABLED === "true",
      allowedActions: (process.env.HWC_MCP_ALLOWED_ACTIONS || "").split(",").filter(Boolean),
    },
    workspace: process.env.HWC_MCP_WORKSPACE || "/home/eric/.nixos/workspace",
    hostname: process.env.HWC_HOSTNAME || "unknown",
  };
}
