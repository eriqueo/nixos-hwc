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
//
// This file also carries the port of write-guard.sh — see THE WRITE GUARD
// below. The two hooks live in one extension because they share one event, one
// evidence ledger and one enable switch. Splitting them would put two producers
// on the same `tool_call` handler for no gain.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { existsSync, realpathSync, statSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

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

// ===========================================================================
// THE WRITE GUARD — port of .claude-config/hooks/write-guard.sh
// ===========================================================================
//
// THE FAILURE, from MISTAKES.md family `destructive-write`. On 2026-08-16 a
// Write on an existing test file, intended to CREATE it, destroyed the five
// tests already in it. Nothing failed: a deleted test is silently absent, the
// suite went green, and the loss surfaced only from `git diff --stat`.
//
// WHY A GUARD AND NOT A RULE. The edit tool already refuses a file it has not
// read. The write tool does not — so the one tool that destroys a whole file is
// the one with no such check. The signal is fully mechanical: does the path
// exist, and has this session looked at it.
//
// WHY BLOCK RATHER THAN CONFIRM. The remedy is one read call, and the damage is
// silent and unrecoverable outside git. A confirm prompt would train
// click-through on a dialog that should never appear during correct work.
//
// THE LEDGER IS AN IN-MEMORY SET, not a file. The Claude Code hook needs a file
// because each hook run is a separate process. An extension instance lives for
// the whole session, so a Set is the entire mechanism.
//
// THE BASH BRANCH IS A WIDER PROXY, not a decision procedure — the same
// concession the shell version states. It drops every target it cannot resolve
// statically, so it misses rather than false-denies, and it exempts anything
// git ignores so build output and dependency trees never reach it.
const seen = new Set<string>();
const enumerated = new Set<string>();

function canonical(p: string): string {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
}

function remember(set: Set<string>, p: string): void {
  if (!p) return;
  set.add(p);
  set.add(canonical(p));
}

function looked(p: string): boolean {
  return seen.has(p) || seen.has(canonical(p));
}

// Verbs that destroy existing content, plus output redirection and `dd of=`.
const DESTRUCTIVE = /(^|[\s|;&(])(rm|mv|cp|tee|truncate|unlink|install)\s|[^>\s0-9]>[^>|]|\s[0-9]*&?>[^>|]|git\s+(checkout|restore)\b|\sof=/;

// Tokens carrying shell expansion cannot be resolved statically. Dropping them
// is the miss-rather-than-false-deny rule made concrete.
const UNRESOLVABLE = /[*?$`(){}\[\]!\\]|^-|^~[^/]/;

function tokens(command: string): string[] {
  return command
    .split(/[\s|;&]+/)
    .filter((t) => t.length > 0 && !UNRESOLVABLE.test(t));
}

function absolute(token: string, cwd: string): string {
  if (token.startsWith("~/")) return resolve(process.env.HOME ?? "", token.slice(2));
  return isAbsolute(token) ? token : resolve(cwd, token);
}

function gitIgnored(p: string, cwd: string): boolean {
  try {
    execFileSync("git", ["check-ignore", "-q", "--", p], { cwd, stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function gitDirty(p: string, cwd: string): boolean {
  try {
    const out = execFileSync("git", ["status", "--porcelain", "--", p], {
      cwd,
      encoding: "utf-8",
    });
    return out.trim().length > 0;
  } catch {
    return false;
  }
}

function describe(p: string): string {
  try {
    const st = statSync(p);
    if (st.isDirectory()) return "a directory";
    return `${st.size} bytes`;
  } catch {
    return "unknown size";
  }
}

const CLOBBER_REASON = (p: string, how: string) =>
  `${how} WOULD DESTROY SOMETHING YOU HAVE NOT LOOKED AT — ${p} already exists ` +
  `(${describe(p)}) and you have not read or listed it this session. Whatever is ` +
  `in it is gone with no error.\n\n` +
  `Read it first. Then either edit the part you meant to change, or proceed ` +
  `knowingly having seen what you are replacing. For a directory, list it with ` +
  `\`find '${p}' -maxdepth 2\` and read the listing — that is what clears this ` +
  `block. Do not use a bare \`ls\` piped to anything: \`ls\` is eza here and ` +
  `returns NOTHING when piped, so an empty result would agree with you for the ` +
  `wrong reason.\n\n` +
  `This is the check that was missing on 2026-08-16, when a write meant to ` +
  `CREATE a test file silently deleted the five tests already in it and the ` +
  `suite stayed green (MISTAKES.md, family destructive-write). A truncated ` +
  `listing is not proof a path is free.`;

const REVERT_REASON = (p: string) =>
  `THIS REVERT WOULD DESTROY UNCOMMITTED WORK — ${p} has changes no commit ` +
  `holds, and \`git checkout\`/\`git restore\` returns the file to HEAD, not to ` +
  `the state before whatever you meant to undo. Both are in the same file, and ` +
  `this command cannot separate them.\n\n` +
  `MISTAKES.md, family destructive-write, twice on 2026-08-23: a seeded test ` +
  `mutation was reverted this way while the fix under test was still ` +
  `uncommitted in the same file, and the fix went with it.\n\n` +
  `Do one of these instead:\n` +
  `  1. Edit the mutated line back by hand. Precise, and it cannot touch ` +
  `anything else.\n` +
  `  2. \`git stash\` first if you really do want the whole file returned to ` +
  `HEAD.\n` +
  `  3. Commit the fix BEFORE seeding any mutation against it, then revert ` +
  `freely.`;

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event: any, ctx: any) => {
    const cwd: string = ctx?.cwd ?? process.cwd();

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

      // A directory cannot be read, so enumerating it is the evidence that
      // clears a later delete. track-evidence.sh records this in Claude Code;
      // here the same fact is observed directly off the command.
      if (/^\s*(find|fd|rg)\b/.test(command)) {
        for (const t of tokens(command)) remember(enumerated, absolute(t, cwd));
      }

      if (!DESTRUCTIVE.test(command)) return;

      const targets = tokens(command)
        .slice(1)
        .map((t) => absolute(t, cwd))
        .filter((p) => existsSync(p));

      // `git checkout -- <path>` / `git restore <path>` on a file carrying
      // uncommitted changes. Checked BEFORE the ledger test, because the ledger
      // cannot see this one: in both 2026-08-23 entries the file had been
      // authored in the same session, so it was already "seen", and the revert
      // destroyed its own uncommitted fix along with the mutation it undid.
      if (/git\s+(checkout|restore)\b/.test(command)) {
        for (const p of targets) {
          if (gitDirty(p, cwd)) return { block: true, reason: REVERT_REASON(p) };
        }
        return;
      }

      for (const p of targets) {
        if (gitIgnored(p, cwd)) continue;
        if (looked(p)) continue;
        if (enumerated.has(p) || enumerated.has(canonical(p))) continue;
        return { block: true, reason: CLOBBER_REASON(p, "THIS COMMAND") };
      }
      return;
    }

    if (event.toolName === "write") {
      const path: string = event.input?.path ?? event.input?.file_path ?? "";
      if (!path) return;
      const abs = absolute(path, cwd);
      // /tmp is definitionally throwaway, and scratch files routinely outlive
      // one session. Carved out so the guard stays about real work.
      if (abs.startsWith("/tmp/")) return;
      if (existsSync(abs) && !looked(abs)) {
        return { block: true, reason: CLOBBER_REASON(abs, "THIS WRITE") };
      }
      remember(seen, abs);
      return;
    }

    if (event.toolName === "edit") {
      const path: string = event.input?.path ?? event.input?.file_path ?? "";
      if (path) remember(seen, absolute(path, cwd));
      return;
    }

    if (event.toolName === "read") {
      const path: string = event.input?.path ?? event.input?.file_path ?? "";
      const bounded = event.input?.limit != null || event.input?.offset != null;
      if (!path) return;
      const abs = absolute(path, cwd);
      if (bounded) {
        remember(seen, abs);
        return;
      }
      try {
        const size = statSync(abs).size;
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
      remember(seen, abs);
    }
  });
}
