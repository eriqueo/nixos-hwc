/**
 * Logger port.
 *
 * Inbound code asks for a Logger; the adapter decides where bytes go
 * (stderr today, OpenTelemetry tomorrow). Core never imports a
 * concrete logger.
 */

import type { LogLevel } from "../config.js";

export interface Logger {
  debug(msg: string, fields?: Record<string, unknown>): void;
  info(msg: string, fields?: Record<string, unknown>): void;
  warn(msg: string, fields?: Record<string, unknown>): void;
  error(msg: string, fields?: Record<string, unknown>): void;
  /** Returns a logger pre-bound with additional structured fields. */
  child(fields: Record<string, unknown>): Logger;
}

export interface LoggerFactoryOpts {
  readonly minLevel: LogLevel;
  readonly serviceName: string;
}
