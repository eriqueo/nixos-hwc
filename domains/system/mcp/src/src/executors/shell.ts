/**
 * Safe shell command executor — uses execFile (no shell interpolation).
 * All tool implementations use this instead of raw child_process.
 */

import { execFile } from "node:child_process";
import type { ExecResult } from "../types.js";
import { log } from "../log.js";

const UNSAFE_PATTERN = /[;&|`$(){}]/;

/**
 * Execute a command safely with parameterized arguments.
 * NEVER passes through a shell — prevents injection.
 */
export function safeExec(
  command: string,
  args: string[],
  options: { timeout?: number; maxBuffer?: number } = {}
): Promise<ExecResult> {
  const { timeout = 15000, maxBuffer = 1024 * 1024 } = options;

  return new Promise((resolve, reject) => {
    // Validate arguments — reject shell metacharacters
    for (const arg of args) {
      if (UNSAFE_PATTERN.test(arg)) {
        reject(new Error(`Unsafe argument rejected: ${arg}`));
        return;
      }
    }

    log.debug("exec", { command, args });

    execFile(command, args, { timeout, maxBuffer }, (error, stdout, stderr) => {
      const exitCode = error && "code" in error ? (error.code as number) : 0;
      resolve({
        exitCode: typeof exitCode === "number" ? exitCode : 1,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      });
    });
  });
}

/**
 * Execute and return stdout, throwing on non-zero exit.
 */
export async function execOrThrow(
  command: string,
  args: string[],
  options?: { timeout?: number; maxBuffer?: number }
): Promise<string> {
  const result = await safeExec(command, args, options);
  if (result.exitCode !== 0) {
    throw new Error(`${command} exited with code ${result.exitCode}: ${result.stderr}`);
  }
  return result.stdout;
}
