import { execFile } from "node:child_process";
import type { ExecResult } from "../types.js";
import { log } from "../log.js";

export interface CommandOptions { timeout?: number; maxBuffer?: number }

// Arguments go directly to execFile, never through a shell. Mutations run once;
// a timeout or failed process must not trigger an automatic retry.
export function executeFile(
  command: string, args: string[], options: CommandOptions = {},
): Promise<ExecResult> {
  const { timeout = 15000, maxBuffer = 1024 * 1024 } = options;
  log.debug("exec", { command, args });
  return new Promise((resolve) => {
    execFile(command, args, { timeout, maxBuffer }, (error, stdout, stderr) => {
      const code = error?.code;
      resolve({
        exitCode: error ? (typeof code === "number" ? code : 1) : 0,
        stdout: stdout?.toString() ?? "",
        stderr: stderr?.toString() ?? "",
      });
    });
  });
}

export function cachedBinary(candidates: readonly string[]): () => Promise<string> {
  // One discovery per resolver; concurrent callers wait for the same probe.
  // Failed discovery is not retained. This never retries an actual action.
  let pending: Promise<string> | undefined;
  return () => pending ??= (async () => {
    for (const bin of candidates) {
      const exists = await new Promise<boolean>((resolve) => {
        execFile(bin, ["--version"], { timeout: 3000 }, (error) => {
          // Some CLIs reject --version. Only ENOENT means try the next path.
          resolve(error?.code !== "ENOENT");
        });
      });
      if (exists) return bin;
    }
    throw new Error(`Binary not found: ${candidates.join(", ")}`);
  })().catch(error => {
    pending = undefined;
    throw error;
  });
}

export function bindCommand(
  binary: () => Promise<string>, defaults: CommandOptions, prefix: readonly string[] = [],
): (args: string[], options?: CommandOptions) => Promise<ExecResult> {
  return async (args, options = {}) =>
    executeFile(await binary(), [...prefix, ...args], { ...defaults, ...options });
}

const UNSAFE_PATTERN = /[;&|`$(){}]/;

// Preserve the existing restrictive policy for infrastructure callers. Mail
// queries and calendar text use executeFile/bindCommand so punctuation is data.
export async function safeExec(
  command: string, args: string[], options: CommandOptions = {},
): Promise<ExecResult> {
  for (const arg of args) {
    if (UNSAFE_PATTERN.test(arg)) throw new Error(`Unsafe argument rejected: ${arg}`);
  }
  return executeFile(command, args, options);
}

export async function execOrThrow(
  command: string, args: string[], options?: CommandOptions,
): Promise<string> {
  const result = await safeExec(command, args, options);
  if (result.exitCode !== 0) {
    throw new Error(`${command} exited with code ${result.exitCode}: ${result.stderr}`);
  }
  return result.stdout;
}
