// Production LlmPort adapter: a single headless `claude -p` completion. The
// binary path is late-bound from the environment (REFINERY_CLAUDE_BIN), falling
// back to `claude` on PATH — no hardcoded store path. This is the real wiring
// for the CLI; tests never touch it (they inject a stub LlmPort).

import { execFile } from "node:child_process";
import { LlmPort } from "../gates/llm-port.js";

export interface ClaudeLlmConfig {
  bin?: string; // default: $REFINERY_CLAUDE_BIN or "claude"
  timeoutMs?: number; // default 120000
  extraArgs?: string[]; // e.g. ["--strict-mcp-config", "--mcp-config", "{}"]
}

export function makeClaudeLlm(cfg: ClaudeLlmConfig = {}): LlmPort {
  const bin = cfg.bin ?? process.env.REFINERY_CLAUDE_BIN ?? "claude";
  const timeout = cfg.timeoutMs ?? 120_000;
  const extra = cfg.extraArgs ?? [];
  return {
    complete(prompt: string): Promise<string> {
      return new Promise((resolve, reject) => {
        execFile(
          bin,
          ["-p", prompt, "--dangerously-skip-permissions", ...extra],
          { timeout, maxBuffer: 32 * 1024 * 1024 },
          (err, stdout) => {
            if (err) reject(err);
            else resolve(stdout.toString());
          },
        );
      });
    },
  };
}
