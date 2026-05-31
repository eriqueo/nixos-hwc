/**
 * Structured-JSON-to-stderr logger. Mirrors hwc-notify's adapter.
 * Same explicit-property pattern (no TS parameter-property shorthand
 * — keeps the code strip-types-compatible just in case).
 */

import type { Logger, LoggerFactoryOpts } from "../ports/log.js";
import type { LogLevel } from "../config.js";

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
};

interface LogRecord {
  ts: string;
  level: LogLevel;
  service: string;
  msg: string;
  [key: string]: unknown;
}

class StderrLogger implements Logger {
  readonly opts: LoggerFactoryOpts;
  readonly boundFields: Record<string, unknown>;

  constructor(opts: LoggerFactoryOpts, boundFields: Record<string, unknown>) {
    this.opts = opts;
    this.boundFields = boundFields;
  }

  private emit(level: LogLevel, msg: string, fields?: Record<string, unknown>): void {
    if (LEVEL_ORDER[level] < LEVEL_ORDER[this.opts.minLevel]) return;
    const record: LogRecord = {
      ts: new Date().toISOString(),
      level,
      service: this.opts.serviceName,
      msg,
      ...this.boundFields,
      ...(fields ?? {}),
    };
    process.stderr.write(JSON.stringify(record) + "\n");
  }

  debug(msg: string, fields?: Record<string, unknown>): void { this.emit("debug", msg, fields); }
  info(msg: string, fields?: Record<string, unknown>): void { this.emit("info", msg, fields); }
  warn(msg: string, fields?: Record<string, unknown>): void { this.emit("warn", msg, fields); }
  error(msg: string, fields?: Record<string, unknown>): void { this.emit("error", msg, fields); }

  child(fields: Record<string, unknown>): Logger {
    return new StderrLogger(this.opts, { ...this.boundFields, ...fields });
  }
}

export function makeStderrLogger(opts: LoggerFactoryOpts): Logger {
  return new StderrLogger(opts, {});
}
