/**
 * Structured logger for Heartwood MCP Server.
 * Logs to stderr (MCP protocol uses stdout for communication).
 */

type LogLevel = "debug" | "info" | "warn" | "error";

const LEVEL_ORDER: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

let currentLevel: LogLevel = "info";

export function setLogLevel(level: LogLevel): void {
  currentLevel = level;
}

function shouldLog(level: LogLevel): boolean {
  return LEVEL_ORDER[level] >= LEVEL_ORDER[currentLevel];
}

function formatLog(
  level: LogLevel,
  message: string,
  data?: Record<string, unknown>
): string {
  const entry: Record<string, unknown> = {
    ts: new Date().toISOString(),
    level,
    msg: message,
  };
  if (data) {
    Object.assign(entry, data);
  }
  return JSON.stringify(entry);
}

export const log = {
  debug(message: string, data?: Record<string, unknown>): void {
    if (shouldLog("debug")) {
      process.stderr.write(formatLog("debug", message, data) + "\n");
    }
  },
  info(message: string, data?: Record<string, unknown>): void {
    if (shouldLog("info")) {
      process.stderr.write(formatLog("info", message, data) + "\n");
    }
  },
  warn(message: string, data?: Record<string, unknown>): void {
    if (shouldLog("warn")) {
      process.stderr.write(formatLog("warn", message, data) + "\n");
    }
  },
  error(message: string, data?: Record<string, unknown>): void {
    if (shouldLog("error")) {
      process.stderr.write(formatLog("error", message, data) + "\n");
    }
  },
};
