import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { parseProfile } from "../src/profile.js";
import { GAUNTLET_CONFIGS } from "../src/profiles/gauntlet-config.js";
import { makeExecuteEffector } from "../src/effectors/execute.js";
import { ClaudePort, GitPort, ReportPort } from "../src/effectors/ports.js";
import { makeItem } from "./helpers.js";

const profilePath = (name: string) =>
  fileURLToPath(new URL(`../../../profiles/${name}`, import.meta.url));

// Minimal stub ports recording the parity-relevant calls.
function stubs(opts: { stdout: string; pristine?: boolean; hasCommits?: boolean }) {
  const calls = { pushed: 0, reverted: 0, addedBranch: undefined as string | undefined };
  const git: GitPort = {
    async resolveBase() { return "origin/main"; },
    async addWorktree(a) { calls.addedBranch = a.branch; },
    async hasCommitsBeyond() { return opts.hasCommits ?? false; },
    async push() { calls.pushed++; },
    async isPristine() { return opts.pristine ?? true; },
    async revert() { calls.reverted++; },
    async removeWorktree() {},
  };
  const claude: ClaudePort = {
    async run() { return { exitCode: 0, stdout: opts.stdout, timedOut: false }; },
  };
  const report: ReportPort = { async exists() { return true; } };
  return { git, claude, report, calls };
}

test("both gauntlet profiles validate and their executeMode matches the gauntlet config", () => {
  const nightly = parseProfile(readFileSync(profilePath("nightly-build.yaml"), "utf8"));
  const sr = parseProfile(readFileSync(profilePath("datax-sr.yaml"), "utf8"));
  assert.equal(nightly.executeMode, GAUNTLET_CONFIGS["nightly-build"].executeMode);
  assert.equal(sr.executeMode, GAUNTLET_CONFIGS["datax-sr"].executeMode);
  // strangler-fig: shipped disabled, not wired into a live engine timer.
  assert.equal(nightly.enabled, false);
  assert.equal(sr.enabled, false);
});

test("parity — nightly-build (write): pushes the branch and succeeds on NIGHTLY-VERDICT: success", async () => {
  const cfg = GAUNTLET_CONFIGS["nightly-build"];
  const s = stubs({ stdout: "NIGHTLY-VERDICT: success", hasCommits: true });
  const eff = makeExecuteEffector(
    {
      repo: "/repo",
      worktree: "/tmp/wt",
      executeMode: cfg.executeMode,
      branch: `${cfg.branchPrefix}fixture`,
      promptWrapper: "WRAP",
      verdictPattern: cfg.verdictPattern,
      successVerdicts: cfg.successVerdicts,
      timeoutMs: 1000,
      reportFile: cfg.reportFile,
    },
    s,
  );
  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "succeeded");
  assert.equal(r.verdict, "success");
  assert.equal(r.pushed, true);
  assert.equal(s.calls.addedBranch, "nightly/fixture");
});

test("parity — nightly-build: a failure verdict does NOT count as success", async () => {
  const cfg = GAUNTLET_CONFIGS["nightly-build"];
  const s = stubs({ stdout: "NIGHTLY-VERDICT: failure", hasCommits: true });
  const eff = makeExecuteEffector(
    {
      repo: "/repo", worktree: "/tmp/wt", executeMode: cfg.executeMode, branch: "nightly/x",
      promptWrapper: "W", verdictPattern: cfg.verdictPattern, successVerdicts: cfg.successVerdicts,
      timeoutMs: 1000, reportFile: cfg.reportFile,
    },
    s,
  );
  const r = await eff.run(makeItem());
  assert.equal(r.verdict, "failure");
  assert.equal(r.outcome, "failed");
});

test("parity — datax-sr (read-only): detached worktree, asserts pristine, succeeds on SR-VERDICT", async () => {
  const cfg = GAUNTLET_CONFIGS["datax-sr"];
  const s = stubs({ stdout: "SR-VERDICT: investigated", pristine: true });
  const eff = makeExecuteEffector(
    {
      repo: "/repo", worktree: "/tmp/wt", executeMode: cfg.executeMode,
      promptWrapper: "W", verdictPattern: cfg.verdictPattern, successVerdicts: cfg.successVerdicts,
      timeoutMs: 1000, reportFile: cfg.reportFile,
    },
    s,
  );
  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "succeeded");
  assert.equal(r.verdict, "investigated");
  assert.equal(r.pristine, true);
  assert.equal(r.pushed, false);
  assert.equal(s.calls.addedBranch, undefined); // detached, no branch
});

test("parity — datax-sr: a dirtied worktree is reverted and fails (PII/pristine guard)", async () => {
  const cfg = GAUNTLET_CONFIGS["datax-sr"];
  const s = stubs({ stdout: "SR-VERDICT: investigated", pristine: false });
  const eff = makeExecuteEffector(
    {
      repo: "/repo", worktree: "/tmp/wt", executeMode: cfg.executeMode,
      promptWrapper: "W", verdictPattern: cfg.verdictPattern, successVerdicts: cfg.successVerdicts,
      timeoutMs: 1000, reportFile: cfg.reportFile,
    },
    s,
  );
  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "failed");
  assert.equal(s.calls.reverted, 1);
});
