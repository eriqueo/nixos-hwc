import type { LogLevel, LogPort } from "../ports/log.ts";

const SEVERITY: Record<LogLevel, number> = {
  debug: 0, info: 1, warn: 2, error: 3,
};

export function createStderrLogger(minLevel: LogLevel = "info"): LogPort {
  const threshold = SEVERITY[minLevel];

  const log = (level: LogLevel, message: string, fields?: Record<string, unknown>) => {
    if (SEVERITY[level] < threshold) return;
    const record = {
      ts: new Date().toISOString(),
      level,
      msg: message,
      ...(fields ?? {}),
    };
    // Single-line JSON per event — structured, journal-friendly.
    console.error(JSON.stringify(record));
  };

  return {
    log,
    debug: (m, f) => log("debug", m, f),
    info:  (m, f) => log("info",  m, f),
    warn:  (m, f) => log("warn",  m, f),
    error: (m, f) => log("error", m, f),
  };
}
