import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { LlmPort } from "../src/gates/llm-port.js";
import { safeReviewId, PrReview } from "../src/review/contract.js";
import { reviewBranch, ReviewInput } from "../src/review/reviewer.js";
import { runMorningReview, MorningReviewConfig } from "../src/review/run.js";
import { GitFactsPort, GitHubPort, ReviewsStore } from "../src/review/ports.js";
import {
  nightlyCardProjects,
  finishedProjects,
  graduateProject,
  reopenProject,
  isProjectComplete,
} from "../src/sources/nightly-cards.js";

// ── Stub ports ───────────────────────────────────────────────────────────────

function stubLlm(verdict: unknown): LlmPort {
  return { async complete() { return JSON.stringify(verdict); } };
}

const GOOD_VERDICT = {
  verdict: "merge-ready",
  whatWasDone: "Refactored the estimator to Zod-validated inputs.",
  whatItMeans: "Inputs are now validated at the boundary; fewer silent bad estimates.",
  recommendation: "merge now",
  risks: [],
};

function stubFacts(over: Partial<Record<string, unknown>> = {}): GitFactsPort {
  return {
    async resolveBase() { return (over.base as string) ?? "origin/main"; },
    async diffstat() { return { files: 2, insertions: 40, deletions: 5 }; },
    async commits() { return ["fix: validate inputs", "test: add cases"]; },
    async isMergeable() { return (over.mergeable as boolean) ?? true; },
  };
}

interface GhCalls {
  created: Array<{ branch: string }>;
  existingFor: Set<string>;
}
function stubGitHub(existingBranches: string[] = []): { github: GitHubPort; calls: GhCalls } {
  const calls: GhCalls = { created: [], existingFor: new Set(existingBranches) };
  let n = 100;
  const github: GitHubPort = {
    async existingPr({ branch }) {
      return calls.existingFor.has(branch)
        ? { url: `https://github.test/pr/exist-${branch}`, number: 7 }
        : null;
    },
    async createPr({ branch }) {
      calls.created.push({ branch });
      n += 1;
      return { url: `https://github.test/pr/${n}`, number: n };
    },
    async mergePr() {},
    async closePr() {},
  };
  return { github, calls };
}

function memStore(): { store: ReviewsStore; saved: PrReview[] } {
  const saved: PrReview[] = [];
  const store: ReviewsStore = {
    async save(r) { saved.push(r); },
    async load(id) { return saved.find((s) => s.id === id) ?? null; },
    async list() { return [...saved]; },
    async delete(id) {
      const i = saved.findIndex((s) => s.id === id);
      if (i >= 0) saved.splice(i, 1);
    },
  };
  return { store, saved };
}

const baseInput = (over: Partial<ReviewInput> = {}): ReviewInput => ({
  id: "estimator/refactor",
  goal: "estimator",
  cardSlug: "refactor",
  title: "Refactor estimator",
  repo: "/repo",
  branch: "nightly/2026-06-17-estimator-refactor",
  base: "origin/main",
  diffstat: { files: 2, insertions: 40, deletions: 5 },
  commits: ["fix: validate inputs"],
  mergeable: true,
  reportText: "Did the thing.",
  cardBody: "Make the estimator validate inputs.",
  reportRelPath: "runs/2026-06-17-estimator-refactor/",
  reviewedAt: "2026-06-17T08:00:00Z",
  ...over,
});

// ── reviewBranch ─────────────────────────────────────────────────────────────

test("reviewBranch maps an LLM verdict to a PrReview (PR fields null, status needs-you)", async () => {
  const r = await reviewBranch(baseInput(), stubLlm(GOOD_VERDICT));
  assert.equal(r.verdict, "merge-ready");
  assert.equal(r.whatWasDone, GOOD_VERDICT.whatWasDone);
  assert.equal(r.recommendation, "merge now");
  assert.deepEqual(r.risks, []);
  assert.equal(r.status, "needs-you");
  assert.equal(r.prUrl, null);
  assert.equal(r.prNumber, null);
  assert.equal(r.mergeable, true);
  assert.deepEqual(r.diffstat, { files: 2, insertions: 40, deletions: 5 });
  assert.equal(r.reportRelPath, "runs/2026-06-17-estimator-refactor/");
});

test("reviewBranch throws on malformed LLM output (fail loud at the boundary)", async () => {
  await assert.rejects(
    () => reviewBranch(baseInput(), stubLlm({ verdict: "maybe" })),
    /failed validation/,
  );
});

// ── safeReviewId ─────────────────────────────────────────────────────────────

test("safeReviewId sanitizes a <goal>/<slug> id into a filename-safe token", () => {
  assert.equal(safeReviewId("estimator/refactor"), "estimator-refactor");
  assert.equal(safeReviewId("a b/c@d"), "a-b-c-d");
  assert.equal(safeReviewId("keep.this_one-2"), "keep.this_one-2");
  assert.equal(safeReviewId("///"), "review");
});

// ── runMorningReview ─────────────────────────────────────────────────────────

function vaultWithDoneCards(): { root: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "refinery-review-"));
  const g = join(root, "_inbox", "nightly_builds", "estimator");
  mkdirSync(g, { recursive: true });
  // A real production-shaped underscore card with an explicit branch and run.
  writeFileSync(
    join(g, "01_mkforce_user_eric_native_services.md"),
    "---\ntitle: Refactor estimator\nstatus: done\nrun: runs/2026-06-17-estimator-mkforce/\nrepo: /repo\n---\n" +
      "Open a PR to branch `nightly/2026-06-17-estimator-mkforce`.\nMake it validate inputs.",
  );
  // a second done card with NO branch in body → derived nightly/<run-name>
  writeFileSync(
    join(g, "02-tests.md"),
    "---\ntitle: Add tests\nstatus: done\nrun: runs/2026-06-17-estimator-tests/\n---\nAdd coverage.",
  );
  // a not-done card → ignored
  writeFileSync(
    join(g, "03-draft.md"),
    "---\ntitle: Draft\nstatus: draft\nrun: runs/x/\n---\nbody",
  );
  // a done card with NO run dir → ignored (nothing was pushed)
  writeFileSync(
    join(g, "04-norun.md"),
    "---\ntitle: No run\nstatus: done\n---\nbody",
  );
  // REPORT for the first card
  const rd = join(root, "runs", "2026-06-17-estimator-mkforce");
  mkdirSync(rd, { recursive: true });
  writeFileSync(join(rd, "REPORT.md"), "Estimator now validates inputs.");
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

test("runMorningReview opens a PR for each done card with a run dir, skips non-done / no-run", async () => {
  const v = vaultWithDoneCards();
  try {
    const cfg: MorningReviewConfig = { vaultDir: v.root, defaultRepo: "/repo" };
    const { github, calls } = stubGitHub();
    const { store, saved } = memStore();
    const summary = await runMorningReview(cfg, {
      facts: stubFacts(),
      github,
      store,
      llm: stubLlm(GOOD_VERDICT),
      clock: () => "2026-06-17T08:00:00Z",
    });

    assert.equal(summary.reviewed, 2, "only the two done+run cards");
    assert.equal(summary.opened, 2);
    assert.equal(summary.byVerdict["merge-ready"], 2);
    assert.equal(calls.created.length, 2);
    // explicit branch honored; second derived from run-name
    const branches = calls.created.map((c) => c.branch).sort();
    assert.deepEqual(branches, [
      "nightly/2026-06-17-estimator-mkforce",
      "nightly/2026-06-17-estimator-tests",
    ]);
    assert.equal(saved.length, 2);
    const refactor = saved.find((s) => s.cardSlug === "mkforce_user_eric_native_services")!;
    assert.equal(refactor.prNumber !== null, true);
    assert.equal(refactor.prUrl !== null, true);

    // Two-way pointer: the PR url lands in the card's `pr:` frontmatter (data,
    // not prose), so the vault card and the PrReview both point at the PR.
    const card1 = readFileSync(join(v.root, "_inbox/nightly_builds/estimator/01_mkforce_user_eric_native_services.md"), "utf8");
    assert.match(card1, new RegExp(`^pr: ${refactor.prUrl}$`, "m"), "reviewed card carries pr:");
    const tests = saved.find((s) => s.cardSlug === "tests")!;
    const card2 = readFileSync(join(v.root, "_inbox/nightly_builds/estimator/02-tests.md"), "utf8");
    assert.match(card2, new RegExp(`^pr: ${tests.prUrl}$`, "m"), "second card carries pr:");
    // ...and the project mirror derives typed pr evidence from that field.
    const proj = nightlyCardProjects(v.root)[0]!;
    assert.ok(
      proj.evidence?.some((e) => e.kind === "pr" && e.ref === refactor.prUrl),
      "mirror item carries the pr as typed evidence",
    );
  } finally {
    v.cleanup();
  }
});

test("runMorningReview backfills a skipped card's pr: from its stored record", async () => {
  const v = vaultWithDoneCards();
  try {
    const cfg: MorningReviewConfig = { vaultDir: v.root, defaultRepo: "/repo" };
    const { github } = stubGitHub();
    const { store, saved } = memStore();
    // A record from a pass BEFORE the card write-back existed: prUrl stored,
    // card frontmatter still empty.
    saved.push({ id: "estimator/mkforce_user_eric_native_services", prUrl: "https://github.test/pr/42" } as PrReview);
    const summary = await runMorningReview(cfg, {
      facts: stubFacts(),
      github,
      store,
      llm: stubLlm(GOOD_VERDICT),
      clock: () => "2026-06-17T08:00:00Z",
    });
    assert.equal(summary.skipped, 1);
    const card = readFileSync(join(v.root, "_inbox/nightly_builds/estimator/01_mkforce_user_eric_native_services.md"), "utf8");
    assert.match(card, /^pr: https:\/\/github\.test\/pr\/42$/m, "skip path backfills the pointer");
  } finally {
    v.cleanup();
  }
});

test("runMorningReview reuses an already-open PR instead of double-opening", async () => {
  const v = vaultWithDoneCards();
  try {
    const cfg: MorningReviewConfig = { vaultDir: v.root, defaultRepo: "/repo" };
    const { github, calls } = stubGitHub(["nightly/2026-06-17-estimator-mkforce"]);
    const { store } = memStore();
    const summary = await runMorningReview(cfg, {
      facts: stubFacts(),
      github,
      store,
      llm: stubLlm(GOOD_VERDICT),
      clock: () => "2026-06-17T08:00:00Z",
    });

    assert.equal(summary.reviewed, 2);
    assert.equal(summary.opened, 1, "only the card without an existing PR is opened");
    assert.equal(calls.created.length, 1);
    assert.deepEqual(calls.created.map((c) => c.branch), [
      "nightly/2026-06-17-estimator-tests",
    ]);
  } finally {
    v.cleanup();
  }
});

test("runMorningReview continues past a single card error and collects it", async () => {
  const v = vaultWithDoneCards();
  try {
    const cfg: MorningReviewConfig = { vaultDir: v.root, defaultRepo: "/repo" };
    const { github } = stubGitHub();
    const { store } = memStore();
    // LLM fails persistently for the second card, succeeds for the first. The
    // runner retries each card 3x (withRetry, since cfe83d1c), so a throw must
    // survive every attempt to land in summary.errors — calls 2..4 all belong
    // to the second card. Costs ~8s of backoff sleep; that's the price of
    // exercising the real error-collection path.
    let call = 0;
    const flakyLlm: LlmPort = {
      async complete() {
        call += 1;
        if (call >= 2) throw new Error("llm boom");
        return JSON.stringify(GOOD_VERDICT);
      },
    };
    const summary = await runMorningReview(cfg, {
      facts: stubFacts(),
      github,
      store,
      llm: flakyLlm,
      clock: () => "2026-06-17T08:00:00Z",
    });

    assert.equal(summary.reviewed, 1, "one card still reviewed despite the other failing");
    assert.equal(summary.errors.length, 1);
    assert.match(summary.errors[0].error, /llm boom/);
  } finally {
    v.cleanup();
  }
});

test("runMorningReview skips a done card that already has a review record (idempotent)", async () => {
  const v = vaultWithDoneCards();
  try {
    const cfg: MorningReviewConfig = { vaultDir: v.root, defaultRepo: "/repo" };
    const { github, calls } = stubGitHub();
    const { store, saved } = memStore();
    // Pre-seed a record for the first card — a prior morning already reviewed it.
    saved.push({ id: "estimator/mkforce_user_eric_native_services" } as PrReview);
    const summary = await runMorningReview(cfg, {
      facts: stubFacts(),
      github,
      store,
      llm: stubLlm(GOOD_VERDICT),
      clock: () => "2026-06-17T08:00:00Z",
    });
    assert.equal(summary.skipped, 1, "the pre-reviewed card is skipped");
    assert.equal(summary.reviewed, 1, "only the un-reviewed card is reviewed");
    assert.deepEqual(calls.created.map((c) => c.branch), [
      "nightly/2026-06-17-estimator-tests",
    ]);
  } finally {
    v.cleanup();
  }
});

// ── exit ramp: graduation / reopen ───────────────────────────────────────────

function vaultWithCompleteProject(): { root: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "refinery-grad-"));
  const g = join(root, "_inbox", "nightly_builds", "done-proj");
  mkdirSync(g, { recursive: true });
  writeFileSync(join(g, "_goal.md"), "---\nmode: nightly\n---\n# Done project\n");
  writeFileSync(
    join(g, "01-a.md"),
    "---\ntitle: A\nstatus: done\nrun: runs/2026-06-17-done-proj-01-a/\nrepo: /repo\n---\nbranch `b1`",
  );
  writeFileSync(
    join(g, "02-b.md"),
    "---\ntitle: B\nstatus: done\nrun: runs/2026-06-17-done-proj-02-b/\nrepo: /repo\n---\nbranch `b2`",
  );
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

test("runMorningReview graduates a project whose every step is done", async () => {
  const v = vaultWithCompleteProject();
  try {
    const cfg: MorningReviewConfig = { vaultDir: v.root, defaultRepo: "/repo" };
    const { github } = stubGitHub();
    const { store } = memStore();
    const summary = await runMorningReview(cfg, {
      facts: stubFacts(),
      github,
      store,
      llm: stubLlm(GOOD_VERDICT),
      clock: () => "2026-06-17T08:00:00Z",
    });
    assert.equal(summary.reviewed, 2);
    assert.deepEqual(summary.graduated, ["done-proj"]);
    // Physically moved: gone from the gauntlet, present on the Finished page.
    assert.equal(nightlyCardProjects(v.root).length, 0);
    const fin = finishedProjects(v.root);
    assert.equal(fin.length, 1);
    assert.equal((fin[0].payload as { goal: string }).goal, "done-proj");
    assert.equal(fin[0].state, "passed");
    // Graduation is the recorded decision that the need was met — the derived
    // outcome is distinct from the execution state (case-ledger law 3).
    assert.equal(fin[0].outcome, "need_met", "graduated project outcome = need_met");
    // Active (ungraduated) projects never claim need_met — checked in
    // nightly-cards.test.ts where an active fixture exists.
    assert.ok(
      existsSync(join(v.root, "_inbox", "nightly_builds", "_finished", "done-proj", "01-a.md")),
    );
  } finally {
    v.cleanup();
  }
});

test("isProjectComplete is true only when every step is done", () => {
  const done = (s: string) => ({ n: "01", file: "01.md", title: "", status: s, step: "", run: "", pr: "" });
  assert.equal(isProjectComplete([done("done"), done("done")]), true);
  assert.equal(isProjectComplete([done("done"), done("queued")]), false);
  assert.equal(isProjectComplete([]), false);
});

test("reopenProject moves a finished project back and queues an amendment step", () => {
  const v = vaultWithCompleteProject();
  try {
    assert.equal(graduateProject(v.root, "done-proj"), true);
    assert.equal(nightlyCardProjects(v.root).length, 0);

    const file = reopenProject(v.root, "done-proj", "also speak the prompt aloud");
    assert.equal(file, "03-amendment.md");
    // Back on the gauntlet with a fresh queued step.
    const active = nightlyCardProjects(v.root);
    assert.equal(active.length, 1);
    assert.equal(finishedProjects(v.root).length, 0);
    const amend = readFileSync(
      join(v.root, "_inbox", "nightly_builds", "done-proj", "03-amendment.md"),
      "utf8",
    );
    assert.match(amend, /status: queued/);
    assert.match(amend, /also speak the prompt aloud/);
  } finally {
    v.cleanup();
  }
});
