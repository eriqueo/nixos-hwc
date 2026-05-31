/**
 * Late-binding config loader.
 *
 * Reads every knob from an env var so the systemd unit (which we control)
 * stays the single source of truth for the runtime environment. No
 * hardcoded paths, ports, secret locations. The NixOS module fills the
 * env from `hwc.notifications.notify.*` options.
 *
 * Per engineering-principles/creating-systems.md §3: "Declare once, derive
 * everywhere."
 */

import { readFileSync } from "node:fs";
import { parseRuntimeConfig, type RuntimeConfig } from "./schemas/runtime-config.js";

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface ServiceConfig {
  readonly bindAddr: string;
  readonly port: number;
  readonly stateDir: string;
  readonly logLevel: LogLevel;
  readonly serviceName: string;
  readonly version: string;
  /** Path to the Nix-generated runtime-config JSON (channels + routes). */
  readonly runtimeConfigFile: string;
  /** Parsed + cross-referenced channels and routes from runtimeConfigFile. */
  readonly runtimeConfig: RuntimeConfig;
}

function readStr(name: string, fallback?: string): string {
  const v = process.env[name];
  if (v && v.length > 0) return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`env: ${name} is required`);
}

function readPort(name: string, fallback: number): number {
  const v = process.env[name];
  if (!v) return fallback;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 1 || n > 65535) {
    throw new Error(`env: ${name} must be a TCP port (1-65535), got: ${v}`);
  }
  return n;
}

function readLogLevel(name: string, fallback: LogLevel): LogLevel {
  const v = process.env[name];
  if (!v) return fallback;
  if (v === "debug" || v === "info" || v === "warn" || v === "error") return v;
  throw new Error(`env: ${name} must be debug|info|warn|error, got: ${v}`);
}

/** Read + parse the runtime-config JSON written by the NixOS module. */
function loadRuntimeConfig(filepath: string): RuntimeConfig {
  let raw: unknown;
  try {
    const text = readFileSync(filepath, "utf8");
    raw = JSON.parse(text);
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`runtime-config: cannot read or parse ${filepath}: ${reason}`);
  }
  return parseRuntimeConfig(raw);
}

export function loadConfig(): ServiceConfig {
  const runtimeConfigFile = readStr("HWC_NOTIFY_RUNTIME_CONFIG_FILE");
  return {
    bindAddr: readStr("HWC_NOTIFY_BIND_ADDR", "127.0.0.1"),
    port: readPort("HWC_NOTIFY_PORT", 11600),
    stateDir: readStr("HWC_NOTIFY_STATE_DIR", "/var/lib/hwc/notify"),
    logLevel: readLogLevel("HWC_NOTIFY_LOG_LEVEL", "info"),
    serviceName: "hwc-notify",
    version: "0.1.0",
    runtimeConfigFile,
    runtimeConfig: loadRuntimeConfig(runtimeConfigFile),
  };
}
