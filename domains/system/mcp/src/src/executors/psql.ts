/**
 * Postgres executor — runs queries via `psql` using peer authentication.
 * Service runs as eric, connects via Unix socket — no sudo needed.
 * Uses execFile (no shell), SQL passed as a single -c argument.
 * Returns parsed JSON rows via json_agg.
 */

import { execFile } from "node:child_process";
import type { ExecResult } from "../types.js";
import { log } from "../log.js";

const DEFAULT_DB = "hwc";

/**
 * Execute a SQL query and return raw stdout/stderr/exitCode.
 */
export function psqlRaw(
  sql: string,
  db: string = DEFAULT_DB,
  options: { timeout?: number } = {},
): Promise<ExecResult> {
  const { timeout = 15000 } = options;

  return new Promise((resolve) => {
    log.debug("psql", { db, sql: sql.slice(0, 80) });

    execFile(
      "psql",
      ["-d", db, "-t", "-A", "-c", sql],
      { timeout, maxBuffer: 1024 * 1024 },
      (error, stdout, stderr) => {
        const exitCode = error && "code" in error ? (error.code as number) : 0;
        resolve({
          exitCode: typeof exitCode === "number" ? exitCode : 1,
          stdout: stdout.toString(),
          stderr: stderr.toString(),
        });
      },
    );
  });
}

/**
 * Execute a SQL query and return parsed JSON rows.
 * Wraps the query in json_agg for structured output.
 */
export async function psqlJson<T = Record<string, unknown>>(
  sql: string,
  db: string = DEFAULT_DB,
): Promise<T[]> {
  const wrapped = `SELECT json_agg(t) FROM (${sql}) t`;
  const result = await psqlRaw(wrapped, db);
  if (result.exitCode !== 0) {
    throw new Error(`psql error: ${result.stderr}`);
  }
  const raw = result.stdout.trim();
  if (!raw || raw === "" || raw === "null") return [];
  return JSON.parse(raw) as T[];
}

/**
 * Execute a SQL statement (INSERT/UPDATE/DELETE) and return affected row count.
 */
export async function psqlExec(
  sql: string,
  db: string = DEFAULT_DB,
): Promise<{ rowCount: number; output: string }> {
  const result = await psqlRaw(sql, db);
  if (result.exitCode !== 0) {
    throw new Error(`psql error: ${result.stderr}`);
  }
  // Parse "UPDATE N" or "INSERT 0 N" from stdout
  const match = result.stdout.match(/(\d+)$/m);
  return {
    rowCount: match ? parseInt(match[1], 10) : 0,
    output: result.stdout.trim(),
  };
}
