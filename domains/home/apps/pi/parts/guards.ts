// domains/home/apps/pi/parts/guards.ts
//
// pi extension: the mechanical half of the agent contract, ported from the
// Claude Code PreToolUse hook (.claude/hooks/enforce-tools.sh). These rules do
// not depend on the model reading or obeying anything — `tool_call` fires
// before execution and a `{ block: true }` return means the call never runs.
// That property matters more here than under Claude Code: DX1 is a ~37B MoE and
// follows prose rules less reliably, so every rule that can be mechanical
// should be.
//
// enforce-tools.sh has two verdicts, deny and ask. pi's tool_call has only
// block, so `ask` is rendered as: confirm when there is a UI, block when there
// is not (-p / --mode json runs get no prompt and must fail closed).

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Leading-command match, mirroring enforce-tools.sh — `foo | grep x` is fine,
// a command that *starts* with grep is the one being replaced by rg.
const LEADING = (bin: string) =>
  new RegExp(`^\\s*(${bin}|command ${bin}|/usr/bin/${bin})\\b`);

const DENY: Array<{ test: RegExp; reason: string }> = [
  { test: LEADING("grep"), reason: "Use rg instead of grep." },
  { test: LEADING("sed"), reason: "Use the edit tool instead of sed." },
];

const CONFIRM: Array<{ test: RegExp; reason: string }> = [
  {
    test: /nixos-rebuild/,
    reason: "nixos-rebuild detected — confirm the target machine with hostname first.",
  },
  {
    test: /git\s+push\s+.*--force/,
    reason: "Force push detected — this can destroy remote history.",
  },
  {
    test: /git\s+(reset\s+--hard|clean\s+-f)/,
    reason: "Destructive git operation — this discards uncommitted work.",
  },
];

// Unbounded reads are the dominant DX1 failure mode, not a style problem: a
// single large tool result floods the context, triggers compaction, and the
// model then fabricates values to fill what compaction dropped (the P1 → M1
// cascade catalogued in the DX1 anti-pattern set). 64 KB is ~16k tokens, well
// under the point where that cascade starts.
const READ_MAX_BYTES = 64 * 1024;

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event: any, ctx: any) => {
    if (event.toolName === "bash") {
      const command: string = event.input?.command ?? "";
      if (!command) return;

      for (const rule of DENY) {
        if (rule.test.test(command)) return { block: true, reason: rule.reason };
      }

      for (const rule of CONFIRM) {
        if (!rule.test.test(command)) continue;
        if (!ctx.hasUI) {
          return { block: true, reason: `${rule.reason} Blocked: non-interactive run.` };
        }
        const ok = await ctx.ui.confirm("Confirm", `${rule.reason}\n\n${command}`);
        if (!ok) return { block: true, reason: "Declined." };
      }
      return;
    }

    if (event.toolName === "read") {
      const path: string = event.input?.path ?? "";
      const bounded = event.input?.limit != null || event.input?.offset != null;
      if (!path || bounded) return;
      try {
        const { statSync } = await import("node:fs");
        const size = statSync(path).size;
        if (size > READ_MAX_BYTES) {
          return {
            block: true,
            reason:
              `${path} is ${Math.round(size / 1024)} KB — too large to read whole. ` +
              `Re-read it with offset/limit, or use rg to find the lines you need. ` +
              `Flooding the context here causes compaction, and compaction is what ` +
              `makes this model invent values it can no longer see.`,
          };
        }
      } catch {
        // Unstattable path (missing, permissions): let the read tool report it.
      }
    }
  });
}
