import { test } from "node:test";
import assert from "node:assert/strict";
import { ClaudePort, ClaudeRunResult, GitPort, ReportPort } from "../src/executors/ports.js";
import {
  composeNativePrompt,
  makeNativeExecutor,
  parseNativeVerdict,
  NativeConfig,
} from "../src/executors/native.js";
import { makeItem } from "./helpers.js";

// ── Stub ports that record calls ───────────────────────────────────────────
interface GitCalls {
  added: Array<{ branch?: string; base: string }>;
  pushed: Array<{ branch: string }>;
  reverted: string[];
  removed: string[];
}

function stubGit(opts: {
  base?: string;
  hasCommits?: boolean;
  pristine?: boolean;
  addThrows?: boolean;
}): { git: GitPort; calls: GitCalls } {
  const calls: GitCalls = { added: [], pushed: [], reverted: [], removed: [] };
  const git: GitPort = {
    async resolveBase() {
      return opts.base ?? "origin/main";
    },
    async addWorktree(a) {
      if (opts.addThrows) throw new Error("worktree add boom");
      calls.added.push({ branch: a.branch, base: a.base });
    },
    async hasCommitsBeyond() {
      return opts.hasCommits ?? false;
    },
    async push(a) {
      calls.pushed.push({ branch: a.branch });
    },
    async isPristine() {
      return opts.pristine ?? true;
    },
    async revert(wt) {
      calls.reverted.push(wt);
    },
    async removeWorktree(a) {
      calls.removed.push(a.worktree);
    },
  };
  return { git, calls };
}

function stubClaude(res: Partial<ClaudeRunResult>): {
  claude: ClaudePort;
  seen: Array<{ readOnly: boolean; prompt: string }>;
} {
  const seen: Array<{ readOnly: boolean; prompt: string }> = [];
  const claude: ClaudePort = {
    async run(a) {
      seen.push({ readOnly: a.readOnly, prompt: a.prompt });
      return { exitCode: 0, stdout: "", timedOut: false, ...res };
    },
  };
  return { claude, seen };
}

const reportPort = (present: boolean): ReportPort => ({
  async exists() {
    return present;
  },
});

const writeCfg = (over: Partial<NativeConfig> = {}): NativeConfig => ({
  repo: "/repo",
  worktree: "/tmp/wt",
  executorMode: "write",
  branch: "refinery/test",
  promptWrapper: "WRAPPER",
  verdictPattern: /NIGHTLY-VERDICT: (success|failure)/,
  successVerdicts: ["success"],
  timeoutMs: 1000,
  reportFile: "REPORT.md",
  ...over,
});

const readonlyCfg = (over: Partial<NativeConfig> = {}): NativeConfig => ({
  repo: "/repo",
  worktree: "/tmp/wt",
  executorMode: "read-only",
  promptWrapper: "WRAPPER",
  verdictPattern: /SR-VERDICT: (investigated|inconclusive)/,
  successVerdicts: ["investigated", "inconclusive"],
  timeoutMs: 1000,
  reportFile: "REPORT.md",
  ...over,
});

// ── Tests ──────────────────────────────────────────────────────────────────

test("composeNativePrompt appends the payload after the wrapper", () => {
  const p = composeNativePrompt("WRAP", makeItem({ payload: { foo: 1 } }));
  assert.ok(p.startsWith("WRAP"));
  assert.ok(p.includes("# THE ITEM"));
  assert.ok(p.includes('"foo": 1'));
});

test("parseNativeVerdict reads both verdict patterns and takes the last match", () => {
  const nightly = "noise\nNIGHTLY-VERDICT: failure\nNIGHTLY-VERDICT: success\n";
  assert.equal(parseNativeVerdict(nightly, /NIGHTLY-VERDICT: (success|failure)/), "success");
  const sr = "SR-VERDICT: inconclusive\n";
  assert.equal(parseNativeVerdict(sr, /SR-VERDICT: (investigated|inconclusive)/), "inconclusive");
  assert.equal(parseNativeVerdict("nothing here", /SR-VERDICT: (\w+)/), null);
});

test("write mode: pushes the branch when there are commits and succeeds on a success verdict", async () => {
  const { git, calls } = stubGit({ hasCommits: true });
  const { claude, seen } = stubClaude({ stdout: "NIGHTLY-VERDICT: success" });
  const eff = makeNativeExecutor(writeCfg(), { git, claude, report: reportPort(true) });

  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "succeeded");
  assert.equal(r.verdict, "success");
  assert.equal(r.pushed, true);
  assert.equal(r.branch, "refinery/test");
  assert.deepEqual(calls.added[0], { branch: "refinery/test", base: "origin/main" });
  assert.deepEqual(calls.pushed, [{ branch: "refinery/test" }]);
  assert.equal(seen[0].readOnly, false);
  assert.deepEqual(calls.removed, ["/tmp/wt"]); // cleaned up by default
});

test("write mode: no commits → no push; missing report → failed", async () => {
  const { git, calls } = stubGit({ hasCommits: false });
  const { claude } = stubClaude({ stdout: "NIGHTLY-VERDICT: success" });
  const eff = makeNativeExecutor(writeCfg(), { git, claude, report: reportPort(false) });

  const r = await eff.run(makeItem());
  assert.equal(r.pushed, false);
  assert.equal(calls.pushed.length, 0);
  assert.equal(r.outcome, "failed"); // report absent
  assert.equal(r.reportPresent, false);
});

test("read-only mode: detached worktree, asserts pristine, succeeds when clean", async () => {
  const { git, calls } = stubGit({ pristine: true });
  const { claude, seen } = stubClaude({ stdout: "SR-VERDICT: investigated" });
  const eff = makeNativeExecutor(readonlyCfg(), { git, claude, report: reportPort(true) });

  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "succeeded");
  assert.equal(r.verdict, "investigated");
  assert.equal(r.pristine, true);
  assert.equal(r.pushed, false);
  assert.equal(calls.added[0].branch, undefined); // detached, no branch
  assert.equal(seen[0].readOnly, true);
  assert.equal(calls.reverted.length, 0);
});

test("read-only mode: dirty worktree is reverted and the run fails", async () => {
  const { git, calls } = stubGit({ pristine: false });
  const { claude } = stubClaude({ stdout: "SR-VERDICT: investigated" });
  const eff = makeNativeExecutor(readonlyCfg(), { git, claude, report: reportPort(true) });

  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "failed"); // pristine violated
  assert.equal(r.pristine, false);
  assert.deepEqual(calls.reverted, ["/tmp/wt"]);
});

test("timeout → failed, and no push even in write mode", async () => {
  const { git, calls } = stubGit({ hasCommits: true });
  const { claude } = stubClaude({ timedOut: true, exitCode: 124, stdout: "" });
  const eff = makeNativeExecutor(writeCfg(), { git, claude, report: reportPort(true) });

  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "failed");
  assert.equal(calls.pushed.length, 0);
});

test("worktree add failure returns a clean failed result without further calls", async () => {
  const { git, calls } = stubGit({ addThrows: true });
  const { claude, seen } = stubClaude({});
  const eff = makeNativeExecutor(writeCfg(), { git, claude, report: reportPort(true) });

  const r = await eff.run(makeItem());
  assert.equal(r.outcome, "failed");
  assert.match(r.detail, /worktree add failed/);
  assert.equal(seen.length, 0); // claude never ran
  assert.equal(calls.removed.length, 0); // nothing to clean up
});

test("write mode requires a branch at construction", () => {
  assert.throws(() => makeNativeExecutor(writeCfg({ branch: undefined }), {
    git: stubGit({}).git,
    claude: stubClaude({}).claude,
    report: reportPort(true),
  }), /write mode requires cfg.branch/);
});
