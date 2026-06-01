/**
 * Late-binding config loader.
 *
 * Every knob comes from an HWC_LEADS_* env var set by the systemd unit.
 * Charter Law 3 — no hardcoded paths/ports/secrets in TS. Mirrors the
 * hwc-notify config layer.
 */

import { readFileSync } from "node:fs";
import type { JtMappings } from "./core/jt-graph.js";

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface ServiceConfig {
  readonly bindAddr: string;
  readonly port: number;
  readonly stateDir: string;
  readonly logLevel: LogLevel;
  readonly serviceName: string;
  readonly version: string;
  /** Base URL of the hwc-notify service. */
  readonly notifyServiceUrl: string;
  /** Trimmed contents of the HMAC secret file, or undefined when disabled. */
  readonly hmacSecret: string | undefined;
  /** Trimmed contents of the JT grant key file, or undefined when disabled. */
  readonly jtGrantKey: string | undefined;
  /** Postgres DSN for hwc.leads. */
  readonly postgresDsn: string;
  /** JT mappings loaded from the Nix-generated JSON file. */
  readonly jtMappings: JtMappings;
  /** SMTP config for the customer-email path. undefined when disabled. */
  readonly smtp: SmtpConfig | undefined;
}

export interface SmtpConfig {
  readonly host: string;
  readonly port: number;
  readonly requireTls: boolean;
  readonly login: string;
  readonly from: string;
  readonly password: string;
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

function loadJtMappings(filepath: string): JtMappings {
  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(filepath, "utf8"));
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`jt mappings file at ${filepath} unreadable: ${reason}`);
  }
  // Trust the Nix-generated file structurally; a malformed object would
  // be a build-time mistake. Cast once.
  return raw as JtMappings;
}

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
    bindAddr: readStr("HWC_LEADS_BIND_ADDR", "127.0.0.1"),
    port: readPort("HWC_LEADS_PORT", 11650),
    stateDir: readStr("HWC_LEADS_STATE_DIR", "/var/lib/hwc/leads"),
    logLevel: readLogLevel("HWC_LEADS_LOG_LEVEL", "info"),
    serviceName: "hwc-leads",
    version: "0.1.0",
    notifyServiceUrl: readStr("HWC_LEADS_NOTIFY_URL", "http://127.0.0.1:11600"),
    hmacSecret: readSecretFile("HWC_LEADS_HMAC_FILE"),
    jtGrantKey: readSecretFile("HWC_LEADS_JT_GRANT_FILE"),
    postgresDsn: readStr("HWC_LEADS_PG_DSN", "postgresql:///hwc"),
    jtMappings: loadJtMappings(readStr("HWC_LEADS_JT_MAPPINGS_FILE")),
    smtp: loadSmtpConfig(),
  };
}

function loadSmtpConfig(): SmtpConfig | undefined {
  const password = readSecretFile("HWC_LEADS_SMTP_PASSWORD_FILE");
  if (password === undefined) return undefined;
  return {
    host: readStr("HWC_LEADS_SMTP_HOST", "127.0.0.1"),
    port: readPort("HWC_LEADS_SMTP_PORT", 1025),
    requireTls: process.env["HWC_LEADS_SMTP_REQUIRE_TLS"] !== "0",
    login: readStr("HWC_LEADS_SMTP_LOGIN"),
    from: readStr("HWC_LEADS_SMTP_FROM"),
    password,
  };
}
