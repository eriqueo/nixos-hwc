// Production ClaudePort: one headless `claude -p` run inside a worktree, shelled
// via execFile like claude-llm.ts. The binary is late-bound from
// REFINERY_CLAUDE_BIN (falling back to `claude` on PATH). `readOnly` selects the
// investigation invocation — MCP tools disabled via an empty strict-mcp-config —
// matching sr_gauntlet's read-only mode; write mode leaves the agent its tools.
// Never exercised under `node --test` (the executor's tests inject a stub);
// only the pure arg-builder below is unit-tested.

import { execFile } from "node:child_process";
import { ClaudePort, ClaudeRunResult } from "../executors/ports.js";

export interface ClaudeHeadlessConfig {
  bin?: string; // default $REFINERY_CLAUDE_BIN or "claude"
}

/** Pure arg-builder (unit-tested). readOnly → empty strict-mcp-config (no tools). */
export function claudeArgs(prompt: string, readOnly: boolean): string[] {
  const base = ["-p", prompt, "--dangerously-skip-permissions"];
  return readOnly ? [...base, "--strict-mcp-config", "--mcp-config", "{}"] : base;
}

export function makeClaudeHeadless(cfg: ClaudeHeadlessConfig = {}): ClaudePort {
  const bin = cfg.bin ?? process.env.REFINERY_CLAUDE_BIN ?? "claude";
  return {
    run({ prompt, cwd, timeoutMs, readOnly }): Promise<ClaudeRunResult> {
      return new Promise((resolve) => {
        execFile(
          bin,
          claudeArgs(prompt, readOnly),
          { cwd, timeout: timeoutMs, maxBuffer: 32 * 1024 * 1024 },
          (err, stdout) => {
            const e = err as (Error & { killed?: boolean; code?: number | string }) | null;
            const timedOut = e?.killed === true;
            const exitCode = typeof e?.code === "number" ? e.code : e ? 1 : 0;
            resolve({ exitCode, stdout: (stdout ?? "").toString(), timedOut });
          },
        );
      });
    },
  };
}
