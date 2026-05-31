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

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface ServiceConfig {
  readonly bindAddr: string;
  readonly port: number;
  readonly stateDir: string;
  readonly logLevel: LogLevel;
  readonly serviceName: string;
  readonly version: string;
  /** Discord webhook URL for the #hwc-alerts channel, read from agenix. */
  readonly discordAlertsWebhookUrl: string | undefined;
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

/**
 * Read a secret from an agenix-mounted file path. Trims trailing newlines.
 * Returns undefined if the env var pointing at the file isn't set — that
 * makes secrets optional at this layer; the caller decides whether
 * absence is fatal (e.g., HTTP shell skips a channel) or fine.
 */
function readSecretFile(name: string): string | undefined {
  const filepath = process.env[name];
  if (!filepath || filepath.length === 0) return undefined;
  try {
    return readFileSync(filepath, "utf8").replace(/\s+$/u, "");
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`secret file at ${name}=${filepath} unreadable: ${reason}`);
  }
}

export function loadConfig(): ServiceConfig {
  return {
    bindAddr: readStr("HWC_NOTIFY_BIND_ADDR", "127.0.0.1"),
    port: readPort("HWC_NOTIFY_PORT", 11600),
    stateDir: readStr("HWC_NOTIFY_STATE_DIR", "/var/lib/hwc/notify"),
    logLevel: readLogLevel("HWC_NOTIFY_LOG_LEVEL", "info"),
    serviceName: "hwc-notify",
    version: "0.1.0",
    discordAlertsWebhookUrl: readSecretFile("HWC_NOTIFY_DISCORD_ALERTS_FILE"),
  };
}
