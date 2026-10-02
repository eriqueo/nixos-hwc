// domains/home/apps/pi/parts/guards.ts
//
// pi extension: the one Pi-only tool rule. Everything Claude Code enforces —
// rg not grep, no sed, write-guard, the destructive-git and nixos-rebuild
// confirmations, the workspace guard — now reaches Pi through the shared hooks
// (claude-config pi/hook-bridge.ts, installed as hwc-hook-bridge.ts). This file
// used to carry hand ports of those; they were a second producer of the same
// policy and were removed on 2026-10-01.
//
// What stays has no Claude hook because it is a property of the model, not of
// the policy: unbounded reads are the dominant DX failure mode. A single large
// tool result floods the context, triggers compaction, and the model then
// fabricates values to fill what compaction dropped (the P1 -> M1 cascade in
// the DX1 anti-pattern set). 64 KB is ~16k tokens, well under the point where
// that cascade starts. `tool_call` fires before execution and `{ block: true }`
// means the call never runs.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { statSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

const READ_MAX_BYTES = 64 * 1024;

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event: any, ctx: any) => {
    if (event.toolName !== "read") return;
    const path: string = event.input?.path ?? event.input?.file_path ?? "";
    if (!path || event.input?.limit != null || event.input?.offset != null) return;
    const cwd: string = ctx?.cwd ?? process.cwd();
    const abs = path.startsWith("~/")
      ? resolve(process.env.HOME ?? "", path.slice(2))
      : isAbsolute(path) ? path : resolve(cwd, path);
    try {
      const size = statSync(abs).size;
      if (size <= READ_MAX_BYTES) return;
      return {
        block: true,
        reason:
          `${path} is ${Math.round(size / 1024)} KB — too large to read whole. ` +
          `Re-read it with offset/limit, or use rg to find the lines you need. ` +
          `Flooding the context here causes compaction, and compaction is what ` +
          `makes this model invent values it can no longer see.`,
      };
    } catch {
      // Unstattable path (missing, permissions): let the read tool report it.
    }
  });
}
