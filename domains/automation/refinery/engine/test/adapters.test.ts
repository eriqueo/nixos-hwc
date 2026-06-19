import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { claudeArgs } from "../src/adapters/claude-headless.js";
import { worktreeAddArgs, pushArgs } from "../src/adapters/git-worktree.js";
import { makeReportFs } from "../src/adapters/report-fs.js";

// These cover the pure arg-construction + the trivial fs port. The git/claude
// adapters themselves spawn subprocesses and are never run under node --test
// (the native executor's tests inject stub ports) — same convention as
// gauntlets/ports.ts nodeProcessPort.

test("claudeArgs: write mode leaves the agent its tools; readOnly disables MCP", () => {
  const write = claudeArgs("do the work", false);
  assert.deepEqual(write, ["-p", "do the work", "--dangerously-skip-permissions"]);
  const ro = claudeArgs("investigate", true);
  assert.ok(ro.includes("--strict-mcp-config"));
  assert.ok(ro.includes("--mcp-config") && ro.includes("{}"));
});

test("worktreeAddArgs: -B <branch> in write mode, --detach in read-only", () => {
  assert.deepEqual(
    worktreeAddArgs("/wt/x", "origin/main", "app-refinement/2026-01-01-x"),
    ["worktree", "add", "-B", "app-refinement/2026-01-01-x", "/wt/x", "origin/main"],
  );
  assert.deepEqual(worktreeAddArgs("/wt/x", "origin/main"), ["worktree", "add", "--detach", "/wt/x", "origin/main"]);
});

test("pushArgs: pushes to origin and never force", () => {
  const a = pushArgs("some/branch");
  assert.deepEqual(a, ["push", "-u", "origin", "some/branch"]);
  assert.ok(!a.includes("--force") && !a.includes("-f"));
});

test("makeReportFs.exists: true only when the report file is present in the worktree", async () => {
  const dir = mkdtempSync(join(tmpdir(), "refinery-report-"));
  try {
    const report = makeReportFs();
    assert.equal(await report.exists({ worktree: dir, reportFile: "REPORT.md" }), false);
    writeFileSync(join(dir, "REPORT.md"), "# done\n");
    assert.equal(await report.exists({ worktree: dir, reportFile: "REPORT.md" }), true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
