// Injected IO boundary for gauntlet dispatch. The dispatch effector is pure
// control flow over these ports — unit tests inject stubs and spawn nothing /
// touch no filesystem. The real adapters below are production-only.

import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

export interface ProcessRunSpec {
  command: string;
  args: string[];
  cwd?: string;
  timeoutMs: number;
}

export interface ProcessRunResult {
  exitCode: number;
  stdout: string;
  stderr: string;
  timedOut: boolean;
}

export interface ProcessPort {
  run(spec: ProcessRunSpec): Promise<ProcessRunResult>;
}

export interface ResultReader {
  exists(path: string): Promise<boolean>;
  readReport(path: string): Promise<string | null>;
}

/** Production ProcessPort — spawns the gauntlet via execFile with a hard timeout.
 *  Never exercised under `node --test` (tests inject stubs). */
export function nodeProcessPort(): ProcessPort {
  return {
    run(spec) {
      return new Promise<ProcessRunResult>((resolve) => {
        execFile(
          spec.command,
          spec.args,
          { cwd: spec.cwd, timeout: spec.timeoutMs, maxBuffer: 16 * 1024 * 1024 },
          (err, stdout, stderr) => {
            const e = err as
              | (Error & { killed?: boolean; code?: number | string; signal?: string })
              | null;
            const timedOut = e?.killed === true;
            const exitCode = typeof e?.code === "number" ? e.code : e ? 1 : 0;
            resolve({
              exitCode,
              stdout: stdout ?? "",
              stderr: stderr ?? "",
              timedOut,
            });
          },
        );
      });
    },
  };
}

/** Production ResultReader — reads the gauntlet's report off disk. */
export function fsResultReader(): ResultReader {
  return {
    async exists(path) {
      return existsSync(path);
    },
    async readReport(path) {
      return existsSync(path) ? readFileSync(path, "utf8") : null;
    },
  };
}
