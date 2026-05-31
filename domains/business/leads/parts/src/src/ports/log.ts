/**
 * Logger port — same shape as hwc-notify so the same StderrLogger
 * adapter pattern lifts in. (Not yet a shared module; if a third
 * service appears, lift to domains/lib/.)
 */

import type { LogLevel } from "../config.js";

export interface Logger {
  debug(msg: string, fields?: Record<string, unknown>): void;
  info(msg: string, fields?: Record<string, unknown>): void;
  warn(msg: string, fields?: Record<string, unknown>): void;
  error(msg: string, fields?: Record<string, unknown>): void;
  child(fields: Record<string, unknown>): Logger;
}

export interface LoggerFactoryOpts {
  readonly minLevel: LogLevel;
  readonly serviceName: string;
}
