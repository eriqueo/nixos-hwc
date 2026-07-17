import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createShell, HttpShellConfig } from "../src/shells/http.js";
import { renderFlowBoard, renderHopperPage, renderNightly, renderFinished, renderFinishedProject, renderSr, renderSrDetail, renderProjectDetail, renderReference, renderReviews, renderBoard } from "../src/shells/render.js";
import { PrReview } from "../src/review/contract.js";
import { LlmPort } from "../src/gates/llm-port.js";
import { Item } from "../src/contracts.js";
import { UNTRIAGED } from "../src/triage.js";
import { fixedClock } from "./helpers.js";

function setup(
  triageLlm: LlmPort,
  opts: { runLlm?: LlmPort; autoRun?: boolean; chain?: boolean } = {},
): { cfg: HttpShellConfig; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "refinery-shell-"));
  const pipelinesDir = join(root, "profiles");
  mkdirSync(pipelinesDir, { recursive: true });
  writeFileSync(
    join(pipelinesDir, "project-ideation.yaml"),
    `pipeline: project-ideation\nlabel: Project Ideation\nsource: http-intake\ngates:\n  - stepwise-refinement\n  - principles-create\n  - premortem\nexecutorMode: none\nexecutors:\n  - spec\n${opts.chain ? "next: build\n" : ""}${opts.autoRun ? "autoRun: true\n" : ""}`,
  );
  if (opts.chain) {
    // The chain successor: a brownfield native `build` pipeline. The board runs
    // its gates in-process then spools native execution (never runs a worktree
    // in tests), so it's safe to kick.
    writeFileSync(
      join(pipelinesDir, "build.yaml"),
      `pipeline: build\nlabel: Build\nsource: chain\ngates:\n  - chestertons-fence\n  - blast-radius\n  - principles-fix\n  - premortem\n  - admission-gates\nexecutorMode: write\nexecutors:\n  - native\ndefaultTraits:\n  mode: brownfield\n  touchesExistingCode: true\n  writeMode: true\nenabled: true\n`,
    );
  }
  return {
    cfg: {
      port: 0,
      itemsDir: join(root, "items"),
      pipelinesDir,
      pipelineStatePath: join(root, "state.json"),
      capsPath: join(root, "caps.json"),
      scratchDir: join(root, "specs"),
      triageProvider: "claude-cli",
      runNowSpoolDir: join(root, "run-now"),
      srRunNowSpoolDir: join(root, "sr-run-now"),
      nativeRunNowSpoolDir: join(root, "native-run"),
      clock: fixedClock,
      triageLlm,
      runLlm: opts.runLlm,
    },
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

// One canned superset response satisfying every gate schema AND the spec schema
// (same shape as the genre-ideation e2e). Lets a full pipeline run deterministically.
function runStub(decision: "pass" | "park" = "pass"): LlmPort {
  const body = {
    decision,
    reason: decision === "pass" ? "ok" : "needs a human call",
    steps: ["scope the idea", "design the core"],
    violations: [],
    hypotheses: ["designed: deliberate"],
    references: [],
    killVectors: [{ vector: "scope creep", severity: "medium" }],
    gates: [{ n: 1, name: "unattended", pass: true }],
    goal: "Build the thing",
    principlesAudit: ["hexagonal: core has no IO"],
    deliverable: "a developed project spec markdown",
  };
  return { async complete() { return JSON.stringify(body); } };
}

const triageStub = (pipeline: string, confidence = 0.9): LlmPort => ({
  async complete() {
    return JSON.stringify({ pipeline, confidence, reason: "stub" });
  },
});

test("intake triages a sentence into a profile item at its first gate", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    await shell.intake("an engine that refines ideas");
    const items = await shell.store.list();
    assert.equal(items.length, 1);
    assert.equal(items[0].pipeline, "project-ideation");
    assert.equal(items[0].step, "stepwise-refinement");
    assert.equal(items[0].state, "pending");
  } finally {
    cleanup();
  }
});

test("intake never fails — a triage LLM error drops the idea into the hopper untriaged", async () => {
  const throwingLlm: LlmPort = { async complete() { throw new Error("claude unavailable"); } };
  const { cfg, cleanup } = setup(throwingLlm);
  try {
    const shell = createShell(cfg);
    await shell.intake("an idea the LLM can't reach");
    const item = (await shell.store.list())[0];
    assert.equal(item.pipeline, UNTRIAGED);
    assert.equal(item.state, "parked");
    assert.match(item.parkedReason!, /triage unavailable: claude unavailable/);
  } finally {
    cleanup();
  }
});

test("intake of an unclassifiable sentence parks an untriaged item", async () => {
  const { cfg, cleanup } = setup(triageStub("nonsense-genre", 0.99));
  try {
    const shell = createShell(cfg);
    await shell.intake("???");
    const item = (await shell.store.list())[0];
    assert.equal(item.pipeline, "untriaged");
    assert.equal(item.state, "parked");
  } finally {
    cleanup();
  }
});

test("amend re-arms a parked item with the note recorded", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const parked: Item = {
      id: "p1", pipeline: "project-ideation", step: "premortem", state: "parked",
      parkedReason: "needs a call", payload: { title: "p1" }, history: [],
    };
    await shell.store.save(parked);
    await shell.amend("p1", "here is the answer");
    const item = (await shell.store.load("p1"))!;
    assert.equal(item.state, "pending");
    assert.equal(item.parkedReason, undefined);
    assert.deepEqual((item.payload as { amendments: string[] }).amendments, ["here is the answer"]);
    assert.equal(item.history.at(-1)!.status, "entered");
  } finally {
    cleanup();
  }
});

test("rewind moves a parked item back to an earlier gate", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const item: Item = {
      id: "r1", pipeline: "project-ideation", step: "premortem", state: "parked",
      payload: { title: "r1" }, history: [],
    };
    await shell.store.save(item);
    await shell.doRewind("r1", "stepwise-refinement", "found an upstream problem");
    const back = (await shell.store.load("r1"))!;
    assert.equal(back.step, "stepwise-refinement");
    assert.equal(back.state, "pending");
    assert.equal(back.history.at(-1)!.status, "rewound");
  } finally {
    cleanup();
  }
});

test("profile toggle flips enabled via the catalog overlay", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    assert.equal(shell.catalog.get("project-ideation")!.enabled, true);
    shell.catalog.setEnabled("project-ideation", false);
    assert.equal(shell.catalog.get("project-ideation")!.enabled, false);
  } finally {
    cleanup();
  }
});

test("setNightly flags a project; bumpNightly changes its priority", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const p: Item = {
      id: "n1", pipeline: "project-ideation", step: "premortem", state: "pending",
      payload: { title: "n1" }, history: [],
    };
    await shell.store.save(p);
    await shell.setNightly("n1", true);
    let item = (await shell.store.load("n1"))!;
    assert.equal(item.schedule, "nightly");
    assert.equal(item.schedulePriority, 0);
    await shell.bumpNightly("n1", "up");
    item = (await shell.store.load("n1"))!;
    assert.equal(item.schedulePriority, 1);
    await shell.setNightly("n1", false);
    assert.equal((await shell.store.load("n1"))!.schedule, "now");
  } finally {
    cleanup();
  }
});

test("promote turns an untriaged idea into a project at its profile's first phase", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const idea: Item = {
      id: "idea1", pipeline: UNTRIAGED, step: "triage", state: "parked",
      parkedReason: "no clear genre", payload: { title: "raw" }, history: [],
    };
    await shell.store.save(idea);
    await shell.promote("idea1", "project-ideation");
    const item = (await shell.store.load("idea1"))!;
    assert.equal(item.pipeline, "project-ideation");
    assert.equal(item.step, "stepwise-refinement");
    assert.equal(item.state, "pending");
    assert.equal(item.history.at(-1)!.status, "entered");
  } finally {
    cleanup();
  }
});

test("renderSr lists SR investigations linking to their REPORT + has a max cap form", () => {
  const profiles = [
    { pipeline: "datax-sr", label: "DataX SR", source: "sr", gates: ["premortem"], executorMode: "read-only",
      executors: ["native"], enabled: true, llmProvider: "claude-cli", color: "#83a598" },
  ];
  const srs: Item[] = [
    { id: "sr:2026-06-12-abc", pipeline: "datax-sr", step: "investigated", state: "passed",
      payload: { title: "Customer X cannot sync", customer: "Acme Co", srStatus: "engaged", run: "investigations/2026-06-12-abc/", hasReport: true, readonly: true, source: "sr_gauntlet investigation" }, history: [] },
  ];
  const html = renderSr(srs, 5, profiles);
  assert.ok(html.includes('class="board"'), "status-lane kanban");
  assert.ok(html.includes("Acme Co") && html.includes("Customer X cannot sync"), "customer (who) + question (why)");
  assert.ok(html.includes("engaged"), "lane labeled by SR status (data-driven)");
  assert.ok(html.includes('href="/project/sr:2026-06-12-abc"'), "card → tabbed detail");
  assert.ok(html.includes('action="/sr/config"') && html.includes('value="5"'));
});

test("renderSrDetail mirrors the SR2 modal — Gameplan/Thread/Details tabs, gameplan default", () => {
  const item: Item = {
    id: "sr:2026-06-12-abc", pipeline: "datax-sr", step: "investigated", state: "passed",
    payload: { title: "Cannot sync inventory", customer: "Acme Co", email: "a@acme.co", srStatus: "engaged", srPhase: "engaged", run: "investigations/2026-06-12-abc/" },
    history: [],
  };
  const html = renderSrDetail(item, {
    gameplan: "## Verdict\nFixed by **reauth**.",
    thread: "- customer: it broke\n- staff: looking",
    context: "plan: CORE",
  });
  // header like the SR2 card
  assert.ok(html.includes("Acme Co") && html.includes("Cannot sync inventory"));
  // the three tabs, gameplan checked by default
  assert.ok(html.includes('for="srt-gameplan"') && html.includes('for="srt-thread"') && html.includes('for="srt-details"'));
  assert.ok(html.includes('id="srt-gameplan" checked'));
  // gameplan rendered as HTML (the solution)
  assert.ok(html.includes("<strong>reauth</strong>"));
  // details tab carries customer context
  assert.ok(html.includes("a@acme.co") && html.includes("CORE"));
});

test("deleteItem removes a project from the store", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const p: Item = {
      id: "del1", pipeline: "project-ideation", step: "premortem", state: "passed",
      payload: { title: "del" }, history: [],
    };
    await shell.store.save(p);
    assert.ok(await shell.store.load("del1"));
    await shell.deleteItem("del1");
    assert.equal(await shell.store.load("del1"), null);
  } finally {
    cleanup();
  }
});

test("renderProjectDetail: editable item shows delete; read-only mirror item hides edits", () => {
  const profiles = [
    { pipeline: "nightly-build", label: "Nightly Builds", source: "vault", gates: ["stepwise-refinement"],
      executorMode: "write", executors: ["native"], enabled: true, llmProvider: "claude-cli", color: "#fe8019" },
  ];
  const project: Item = {
    id: "e1", pipeline: "nightly-build", step: "premortem", state: "passed",
    payload: { title: "editable" }, history: [],
  };
  assert.ok(renderProjectDetail(project, profiles, profiles).includes('action="/delete"'));

  const mirror: Item = {
    id: "nb:goal/01-x", pipeline: "nightly-build", step: "queued", state: "pending",
    payload: { title: "mirror card", readonly: true, run: "runs/2026-06-15-x/", pr: "branch x" }, history: [], schedule: "nightly",
  };
  const d = renderProjectDetail(mirror, profiles, profiles);
  assert.ok(d.includes("read-only"));
  assert.ok(d.includes("runs/2026-06-15-x/"));
  assert.ok(!d.includes('action="/delete"'), "mirror cards aren't deletable");
  assert.ok(!d.includes('action="/amend"'), "mirror cards aren't editable");
});

test("renderProjectDetail shows actions + nightly toggle; renderNightly is a status-lane kanban", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executorMode: "none",
      executors: ["spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26" },
  ];
  const parked: Item = {
    id: "d1", pipeline: "project-ideation", step: "premortem", state: "parked",
    parkedReason: "needs a call", payload: { title: "a project" }, history: [], schedule: "nightly",
  };
  const detail = renderProjectDetail(parked, profiles, profiles);
  assert.ok(detail.includes('action="/amend"'));
  assert.ok(detail.includes('action="/rewind"'));
  assert.ok(detail.includes('action="/nightly/toggle"'));
  assert.ok(detail.includes("remove from nightly"), "nightly already on → offers removal");
  assert.ok(detail.includes('value="stepwise-refinement"'));

  const idea: Item = {
    id: "d2", pipeline: UNTRIAGED, step: "triage", state: "parked",
    payload: { title: "raw idea" }, history: [],
  };
  assert.ok(renderProjectDetail(idea, profiles, profiles).includes('action="/promote"'), "ideas can be promoted");

  // A read-only nightly-build mirror card carries its vault-backed queue control inline.
  const mirror: Item = {
    id: "nb:goal/01-x", pipeline: "nightly-build", step: "1/3 steps", state: "parked",
    payload: { title: "mirror card", readonly: true, source: "nightly-builds project",
      stepsDone: 1, stepsTotal: 3, queuedCount: 0, mode: "nightly", nextStatus: "draft" },
    history: [], schedule: "nightly",
  };
  const n = renderNightly([parked, mirror], 1, profiles, profiles);
  assert.ok(n.includes('class="board"'), "nightly is a status-lane kanban");
  assert.ok(n.includes("a project") && n.includes('href="/project/d1"'), "project as a click-through card");
  assert.ok(n.includes('action="/card/queue"') && n.includes("✅ queue"), "mirror card queues inline");
  assert.ok(n.includes('formaction="/card/run-now"'), "mirror card runs inline");
  assert.ok(n.includes('action="/nightly/config"'));
});

test("a parked card surfaces the gate's `asks` as a 'to unblock, decide' list + an answer box", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executorMode: "none",
      executors: ["spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26" },
  ];
  const parked: Item = {
    id: "ask1", pipeline: "project-ideation", step: "premortem", state: "parked",
    parkedReason: "high-severity vectors need a scoping call",
    payload: {
      title: "a project",
      verdicts: {
        premortem: { decision: "park", reason: "scope", output: {
          decision: "park", reason: "scope",
          asks: ["Decide: single .json bundle or per-slide files?", "Decide: cap the slide count?"],
        } },
      },
    },
    history: [],
  };
  const d = renderProjectDetail(parked, profiles, profiles);
  assert.ok(d.includes("To unblock, decide:"), "shows the actionable header");
  assert.ok(d.includes("single .json bundle or per-slide files?"), "renders ask 1");
  assert.ok(d.includes("cap the slide count?"), "renders ask 2");
  assert.ok(d.includes('action="/amend"') && d.includes("answer"), "answer box framed to answer the asks");
});

test("a native pipeline shows the Target repo picker (required when unset; set-repo route)", () => {
  const nativeProfile = [
    { pipeline: "app-refinement", label: "App Refinement", source: "cli-input",
      gates: ["chestertons-fence", "premortem"], executorMode: "write",
      executors: ["native"], enabled: true, llmProvider: "claude-cli", color: "#b48ead" },
  ];
  const unset: Item = {
    id: "ar1", pipeline: "app-refinement", step: "chestertons-fence", state: "pending",
    payload: { title: "refine some-app" }, history: [],
  };
  const d = renderProjectDetail(unset, nativeProfile, nativeProfile);
  assert.ok(d.includes('action="/set-repo"'), "repo picker form present");
  assert.ok(d.includes("Target repo") && d.includes("required"), "prominent + required when unset");
  assert.ok(d.includes("queues native execution"), "run hint is native-aware, not spec");

  const withRepo = renderProjectDetail(
    { ...unset, payload: { title: "x", repo: "/home/eric/600_apps/transcript-formatter" } },
    nativeProfile, nativeProfile,
  );
  assert.ok(withRepo.includes('value="/home/eric/600_apps/transcript-formatter"'), "current repo shown");
  assert.ok(withRepo.includes("update repo"), "offers update when set");
});

test("a completed project-ideation card shows its spec as the outcome + next step, not a dead end", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executorMode: "none",
      executors: ["spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26" },
  ];
  const done: Item = {
    id: "done1", pipeline: "project-ideation", step: "premortem", state: "passed",
    payload: {
      title: "a finished idea",
      executorResult: { outcome: "succeeded", verdict: "spec-written", detail: "wrote spec",
        output: { specPath: "/var/lib/refinery/specs/done1-spec.md",
          spec: { goal: "Ship the thing", steps: ["P1: do x", "P2: do y"], deliverable: "a merged module" } } },
    },
    // ran stepwise + premortem; principles-create skipped (greenfield gate n/a here)
    history: [
      { step: "stepwise-refinement", status: "passed", at: "t1" },
      { step: "premortem", status: "passed", at: "t2" },
      { step: "spec", status: "passed", at: "t3", note: "wrote spec" },
    ],
  };
  const d = renderProjectDetail(done, profiles, profiles);
  assert.ok(d.includes("✓ Done — outcome"), "leads with a done/outcome section");
  assert.ok(d.includes("developed spec") && d.includes("Ship the thing"), "renders the produced spec inline");
  assert.ok(d.includes("P1: do x"), "shows the spec steps");
  assert.ok(d.includes("<b>Next:</b>"), "states a next step");
  assert.ok(d.includes("done1-spec.md"), "links/shows the spec path");
  assert.ok(d.includes("↻ re-run"), "re-run is demoted, not the prominent action");
  assert.ok(!d.includes("▶ run pipeline now"), "no prominent run-now on a finished item");
  assert.ok(d.includes("gate-dot skipped") || d.includes("ndot skipped"), "skipped gate (principles-create) renders skipped, not pending");
});

test("setRepo binds (and clears) payload.repo on an item", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    await shell.store.save({ id: "sr1", pipeline: "app-refinement", step: "chestertons-fence", state: "pending", payload: { title: "x" }, history: [] });
    await shell.setRepo("sr1", "  /home/eric/600_apps/transcript-formatter  ");
    assert.equal(((await shell.store.load("sr1"))!.payload as { repo?: string }).repo, "/home/eric/600_apps/transcript-formatter");
    await shell.setRepo("sr1", "   "); // blank clears it
    assert.equal(((await shell.store.load("sr1"))!.payload as { repo?: string }).repo, undefined);
  } finally { cleanup(); }
});

test("renderFinished is a plain grid of click-through cards; renderFinishedProject is read-only + send-back", () => {
  const finished: Item = {
    id: "nbf:my-goal", pipeline: "nightly-build", step: "3/3 steps", state: "passed",
    payload: {
      title: "graduated project", goal: "my-goal", readonly: true, finished: true,
      source: "nightly-builds (finished)", stepsDone: 3, stepsTotal: 3,
      steps: [
        { n: "01", file: "01-x.md", title: "step one", status: "done", step: "1 of 3", run: "runs/2026-06-15-x/", pr: "branch `feat/x` (3 files)" },
        { n: "02", file: "02-y.md", title: "step two", status: "done", step: "2 of 3", run: "", pr: "https://github.com/eriqueo/x/pull/9" },
      ],
    },
    history: [], schedule: "nightly",
  };

  const grid = renderFinished([finished], [], []);
  assert.ok(grid.includes('class="wrap"') && !grid.includes('class="board"'), "finished is a plain grid, not a lane board");
  assert.ok(grid.includes('href="/project/nbf:my-goal"'), "finished card clicks through to its detail");
  assert.ok(grid.includes("1 finished project"), "header count");
  assert.ok(renderFinished([], [], []).includes("no finished projects yet"), "empty state");

  const d = renderFinishedProject(finished);
  assert.ok(d.includes('action="/card/sendback"'), "send-back form");
  assert.ok(d.includes('name="amendment"') && d.includes('name="back"'), "amendment + back fields");
  assert.ok(d.includes('value="nbf:my-goal"'), "hidden id");
  assert.ok(d.includes("← finished"), "back link");
  assert.ok(d.includes("branch") && d.includes("feat/x"), "prose pr shown escaped");
  assert.ok(d.includes('href="https://github.com/eriqueo/x/pull/9"'), "url pr linkified");
  assert.ok(!d.includes('action="/card/queue"') && !d.includes('action="/card/run-now"') && !d.includes('action="/card/mode"'), "read-only: no queue/run/mode controls");
});

const DOMAINS = {
  domains: [{ key: "datax", label: "DataX", color: "#b16286", match: ["datax"] }],
  fallback: { key: "misc", label: "Misc", color: "#a7aaad", match: [] },
};

test("renderFlowBoard: cards colored by DOMAIN, genre as a badge, inline controls", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executorMode: "none",
      executors: ["spec"], enabled: true, llmProvider: "claude-cli", color: "#a3be8c" },
  ];
  const parked: Item[] = [
    { id: "x", pipeline: "project-ideation", step: "premortem", state: "parked",
      parkedReason: "needs a call", payload: { title: "a project", domain: "datax" }, history: [] },
  ];
  const g = renderFlowBoard(parked, profiles, profiles, DOMAINS);
  assert.ok(g.includes("a project"));
  assert.ok(g.includes("#b16286"), "card colored by its DOMAIN, not the genre");
  assert.ok(g.includes(">DataX<"), "domain tag in the card header");
  assert.ok(g.includes(">Project Ideation<"), "genre/pipeline shown as a badge");
  assert.ok(g.includes('href="/project/x"'), "title links to its detail page");
  // Inline per-card controls: status/lane dropdown, genre re-pick, run, delete.
  assert.ok(g.includes('action="/status"') && g.includes('name="status"'), "lane dropdown on the card");
  assert.ok(g.includes('action="/run"'), "run button on the card");
  assert.ok(g.includes('action="/delete"'), "delete on the card");
  assert.ok(g.includes('name="back" value="/"'), "actions redirect back to the board");
  assert.ok(!g.includes('action="/amend"'), "amend (needs a note) stays on the detail page");
});

test("renderHopperPage: stage-lane kanban; a Ready idea promotes inline", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement"], executorMode: "none", executors: ["spec"],
      enabled: true, llmProvider: "claude-cli", color: "#a3be8c" },
  ];
  // A captured idea (no promote yet) and a ready idea (promote shown).
  const ideas: Item[] = [
    { id: "i1", pipeline: UNTRIAGED, stage: "captured", state: "parked",
      payload: { title: "datax: raw idea", input: "datax: raw idea" }, history: [] },
    { id: "i2", pipeline: UNTRIAGED, stage: "ready", state: "parked",
      payload: { title: "shaped idea", input: "shaped idea" }, history: [] },
  ];
  const h = renderHopperPage(ideas, profiles, profiles, DOMAINS);
  assert.ok(h.includes('action="/intake"'));
  assert.ok(h.includes('class="board"') && h.includes(">Captured<") && h.includes(">Ready<"), "stage-lane kanban");
  assert.ok(h.includes("#b16286") && h.includes(">DataX<"), "idea colored + tagged by parsed domain");
  assert.ok(h.includes('action="/stage"'), "inline stage advancer");
  assert.ok(h.includes('action="/domain"'), "inline domain picker");
  // promote only on the Ready idea, into project-ideation, with immediate|nightly.
  assert.ok(h.includes('action="/promote"') && h.includes('value="project-ideation"'), "Ready idea promotes inline");
  assert.ok(h.includes('value="immediate"') && h.includes('value="nightly"'), "immediate vs nightly scheduling");
});

test("setStatus moves an engine item to another lane (manual board override)", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const p: Item = {
      id: "mv1", pipeline: "project-ideation", step: "premortem", state: "pending",
      payload: { title: "movable" }, history: [],
    };
    await shell.store.save(p);
    await shell.setStatus("mv1", "parked");
    const moved = await shell.store.load("mv1");
    assert.equal(moved!.state, "parked");
    assert.equal(moved!.history.at(-1)!.note, "status set on board");
    // invalid status is ignored (no throw, no change)
    await shell.setStatus("mv1", "bogus");
    assert.equal((await shell.store.load("mv1"))!.state, "parked");
  } finally {
    cleanup();
  }
});

test("setStage advances a hopper idea; setDomain overrides its color/tag", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const idea: Item = {
      id: "h1", pipeline: UNTRIAGED, stage: "captured", state: "parked",
      payload: { title: "an idea", input: "an idea" }, history: [],
    };
    await shell.store.save(idea);
    await shell.setStage("h1", "ready");
    assert.equal((await shell.store.load("h1"))!.stage, "ready", "stage advanced");
    await shell.setStage("h1", "bogus"); // invalid stage ignored
    assert.equal((await shell.store.load("h1"))!.stage, "ready");
    await shell.setDomain("h1", "datax");
    assert.equal(((await shell.store.load("h1"))!.payload as { domain?: string }).domain, "datax", "domain override stored");
    // stage move only applies to untriaged ideas (a triaged project is unaffected)
    const proj: Item = { id: "p1", pipeline: "project-ideation", step: "premortem", state: "pending", payload: {}, history: [] };
    await shell.store.save(proj);
    await shell.setStage("p1", "ready");
    assert.equal((await shell.store.load("p1"))!.step, "premortem", "stage move ignores triaged projects");
  } finally {
    cleanup();
  }
});

test("promote(immediate) runs the pipeline now; promote(nightly) flags it", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass") });
  try {
    const shell = createShell(cfg);
    const ready: Item = {
      id: "r1", pipeline: UNTRIAGED, stage: "ready", state: "parked",
      payload: { title: "ready idea", input: "an engine that refines ideas into specs" }, history: [],
    };
    await shell.store.save(ready);
    await shell.promote("r1", "project-ideation", "immediate");
    const after = await shell.store.load("r1");
    assert.equal(after!.pipeline, "project-ideation", "promoted into the pipeline");
    // immediate → the run effector executed (spec written, passed)
    assert.equal(after!.state, "passed");
    assert.ok(existsSync(join(cfg.scratchDir, "r1-spec.md")), "immediate promote ran the pipeline now");

    const ready2: Item = {
      id: "r2", pipeline: UNTRIAGED, stage: "ready", state: "parked",
      payload: { title: "later idea", input: "later idea" }, history: [],
    };
    await shell.store.save(ready2);
    await shell.promote("r2", "project-ideation", "nightly");
    const n = await shell.store.load("r2");
    assert.equal(n!.schedule, "nightly", "nightly promote flags for the overnight batch");
  } finally {
    cleanup();
  }
});

test("runItem runs a pending engine item through the pipeline and writes a spec", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass") });
  try {
    const shell = createShell(cfg);
    await shell.intake("an engine that refines ideas into specs");
    const id = (await shell.store.list())[0]!.id;
    await shell.runItem(id);
    const item = await shell.store.load(id);
    assert.equal(item!.step, "premortem");
    assert.equal(item!.state, "passed");
    assert.equal(item!.history.at(-1)!.step, "spec");
    assert.ok(existsSync(join(cfg.scratchDir, `${id}-spec.md`)), "developed spec written to scratch dir");
  } finally {
    cleanup();
  }
});

test("kickRun marks the item running, then completes it — the Run button path", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass") });
  try {
    const shell = createShell(cfg);
    await shell.intake("a fresh idea to develop");
    const id = (await shell.store.list())[0]!.id;
    await shell.kickRun(id); // returns the run promise in tests (prod fire-and-forgets)
    assert.equal((await shell.store.load(id))!.state, "passed");
  } finally {
    cleanup();
  }
});

test("an autoRun genre runs the pipeline on intake — no button press (incoming SR tickets)", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass"), autoRun: true });
  try {
    const shell = createShell(cfg);
    await shell.intake("a ticket that should process itself on arrival");
    await new Promise((r) => setTimeout(r, 150)); // let the fire-and-forget run finish
    assert.equal((await shell.store.list())[0]!.state, "passed", "auto-ran to completion");
  } finally {
    cleanup();
  }
});

test("renderProjectDetail shows a Run button for a pending engine item; running hides it", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executorMode: "none",
      executors: ["spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26" },
  ];
  const pending: Item = {
    id: "r1", pipeline: "project-ideation", step: "stepwise-refinement", state: "pending",
    payload: { title: "an idea", input: "an idea" }, history: [],
  };
  const d = renderProjectDetail(pending, profiles, profiles);
  assert.ok(d.includes('action="/run"'), "pending engine item exposes the Run form");
  assert.ok(d.includes("run pipeline now"));

  const running = renderProjectDetail({ ...pending, state: "running" }, profiles, profiles);
  assert.ok(running.includes("running the project-ideation pipeline"), "running shows progress");
  assert.ok(!running.includes('action="/run"'), "no second Run while already running");
});

test("requestSrRunNow writes a sanitized <srId> spool file (no path traversal)", () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    shell.requestSrRunNow("../../etc/passwd");
    const files = readdirSync(cfg.srRunNowSpoolDir);
    assert.equal(files.length, 1);
    assert.ok(!files[0]!.includes("/"), "sanitized to a bare filename — no traversal");
    assert.equal(files[0], "....etcpasswd");
  } finally {
    cleanup();
  }
});

test("requestSrRunNow drops a clean srId verbatim into the spool", () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    createShell(cfg).requestSrRunNow("SR-abc123");
    assert.equal(readFileSync(join(cfg.srRunNowSpoolDir, "SR-abc123"), "utf8").trim(), "SR-abc123");
  } finally {
    cleanup();
  }
});

test("renderSrDetail shows a re-investigate button only when the SR carries an srId", () => {
  const withId: Item = {
    id: "sr:2026-06-15-abc", pipeline: "datax-sr", step: "done", state: "passed",
    payload: { title: "login broken", customer: "Acme", srId: "abc123", readonly: true }, history: [],
  };
  const html = renderSrDetail(withId, { gameplan: "## Verdict", thread: null, context: null });
  assert.ok(html.includes('action="/sr/run-now"'), "re-investigate form present");
  assert.ok(html.includes('value="abc123"'), "srId carried in the form");
  assert.ok(html.includes("re-investigate now"));

  const noId: Item = { ...withId, payload: { title: "x", readonly: true } };
  assert.ok(
    !renderSrDetail(noId, { gameplan: null, thread: null, context: null }).includes('action="/sr/run-now"'),
    "no srId → no button",
  );
});

test("app-refinement: the board runs gates in-process, then SPOOLS native execution (no in-process executor)", async () => {
  const root = mkdtempSync(join(tmpdir(), "refinery-native-"));
  const pipelinesDir = join(root, "pipelines");
  mkdirSync(pipelinesDir, { recursive: true });
  writeFileSync(
    join(pipelinesDir, "app-refinement.yaml"),
    [
      "pipeline: app-refinement",
      "label: App Refinement",
      "source: cli-input",
      "gates:",
      "  - chestertons-fence",
      "  - blast-radius",
      "  - principles-fix",
      "  - premortem",
      "  - admission-gates",
      "executorMode: write",
      "executors:",
      "  - native",
      "defaultTraits:",
      "  mode: brownfield",
      "  touchesExistingCode: true",
      "  writeMode: true",
      "",
    ].join("\n"),
  );

  const nativeRunNowSpoolDir = join(root, "native-run");
  const cfg: HttpShellConfig = {
    port: 0,
    itemsDir: join(root, "items"),
    pipelinesDir,
    pipelineStatePath: join(root, "state.json"),
    capsPath: join(root, "caps.json"),
    scratchDir: join(root, "specs"),
    triageProvider: "claude-cli",
    runNowSpoolDir: join(root, "run-now"),
    srRunNowSpoolDir: join(root, "sr-run-now"),
    nativeRunNowSpoolDir,
    clock: fixedClock,
    triageLlm: triageStub("app-refinement"),
    runLlm: runStub("pass"),
    nativeRepo: "/tmp/some-app",
  };

  try {
    const shell = createShell(cfg);
    const item: Item = {
      id: "ar1",
      pipeline: "app-refinement",
      step: "chestertons-fence",
      state: "pending",
      payload: { title: "refine some-app", input: "refine some-app", repo: "/tmp/some-app", traits: { mode: "brownfield", touchesExistingCode: true, writeMode: true } },
      history: [],
    };
    await shell.store.save(item);
    await shell.runItem("ar1");

    const done = (await shell.store.load("ar1"))!;
    // Gates passed in-process → item is marked running and queued for the
    // privileged native runner; the board never ran the executor.
    assert.equal(done.state, "running", "clean gate pass → marked running, awaiting native execution");
    const pl = done.payload as Record<string, any>;
    assert.equal(pl.executorResult, undefined, "the board did NOT run the native executor (no executorResult yet)");
    assert.ok(pl.verdicts?.["principles-fix"], "gate verdicts persisted to payload");
    assert.equal(done.history.at(-1)!.note, "queued for native execution");

    // A spool file (the item id) was dropped for refinery-run-native to drain.
    const spooled = readdirSync(nativeRunNowSpoolDir);
    assert.deepEqual(spooled, ["ar1"], "execute request spooled by item id");
    assert.equal(readFileSync(join(nativeRunNowSpoolDir, "ar1"), "utf8").trim(), "ar1");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("the board refuses to native-run an external-gauntlet pipeline (double-exec guard)", async () => {
  const root = mkdtempSync(join(tmpdir(), "refinery-guard-"));
  const pipelinesDir = join(root, "pipelines");
  mkdirSync(pipelinesDir, { recursive: true });
  writeFileSync(
    join(pipelinesDir, "nightly-build.yaml"),
    "pipeline: nightly-build\nlabel: Nightly\nsource: vault\ngates:\n  - premortem\nexecutorMode: write\nexecutors:\n  - native\nenabled: false\n",
  );
  const cfg: HttpShellConfig = {
    port: 0, itemsDir: join(root, "items"), pipelinesDir, pipelineStatePath: join(root, "s.json"),
    capsPath: join(root, "c.json"), scratchDir: join(root, "specs"), triageProvider: "claude-cli",
    runNowSpoolDir: join(root, "rn"), srRunNowSpoolDir: join(root, "srn"), nativeRunNowSpoolDir: join(root, "nrn"), clock: fixedClock,
    triageLlm: triageStub("nightly-build"), runLlm: runStub("pass"), nativeRepo: "/tmp/x",
  };
  try {
    const shell = createShell(cfg);
    await shell.store.save({ id: "nb1", pipeline: "nightly-build", step: "premortem", state: "pending", payload: { title: "x" }, history: [] });
    await assert.rejects(() => shell.runItem("nb1"), /owned by an external gauntlet/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// ── Step 4 UI redesign: gate-dot strip, pipeline node strip, /reference, /reviews ──

const FLOW_PROFILE = {
  pipeline: "app-refinement", label: "App Refinement", source: "cli-input",
  gates: ["chestertons-fence", "principles-fix", "premortem"], executorMode: "write",
  executors: ["native"], enabled: true, llmProvider: "claude-cli", color: "#83a598",
};

test("gate-dot progress strip renders on a project card from history; ideas get none", () => {
  const project: Item = {
    id: "gd1", pipeline: "app-refinement", step: "premortem", state: "running",
    payload: { title: "a refinement", domain: "datax" },
    history: [
      { step: "chestertons-fence", status: "passed", at: "t1" },
      { step: "principles-fix", status: "parked", at: "t2" },
      { step: "premortem", status: "running", at: "t3" },
    ],
  };
  const g = renderFlowBoard([project], [FLOW_PROFILE], [FLOW_PROFILE], DOMAINS);
  assert.ok(g.includes('class="gate-dots"'), "gate-dot strip present");
  assert.ok(g.includes('class="gate-dot passed"'), "passed gate dot");
  assert.ok(g.includes('class="gate-dot parked"'), "parked gate dot");
  assert.ok(g.includes('gate-dot running current'), "current step ringed");
  assert.ok(g.includes('class="gate-dot pending"'), "executor step pending (no history)");
  assert.ok(g.includes('title="premortem: running"'), "per-dot tooltip = step: state");

  // an untriaged idea has no pipeline → no strip
  const idea: Item = { id: "i9", pipeline: UNTRIAGED, stage: "captured", state: "parked",
    payload: { title: "raw", input: "raw" }, history: [] };
  assert.ok(!renderHopperPage([idea], [FLOW_PROFILE], [FLOW_PROFILE], DOMAINS).includes('class="gate-dots"'),
    "ideas get no gate-dot strip");
});

test("renderProjectDetail pipeline node strip surfaces a verdict + executor result + triage", () => {
  const item: Item = {
    id: "nd1", pipeline: "app-refinement", step: "premortem", state: "passed",
    payload: {
      title: "node strip",
      triage: { confidence: 0.91, reason: "clearly an app refinement" },
      verdicts: { "principles-fix": { decision: "pass", reason: "hexagonal kept", output: "no violations found" } },
      executorResult: { outcome: "succeeded", verdict: "success", reportPresent: true, branch: "app-refinement/2026-06-19-x", pristine: null, pushed: true, detail: "pushed a branch", output: { files: 3 } },
    },
    history: [
      { step: "chestertons-fence", status: "passed", at: "t1" },
      { step: "principles-fix", status: "passed", at: "t2" },
      { step: "premortem", status: "passed", at: "t3" },
      { step: "native", status: "passed", at: "t4" },
    ],
  };
  const d = renderProjectDetail(item, [FLOW_PROFILE], [FLOW_PROFILE], DOMAINS);
  assert.ok(d.includes("<h2>Pipeline</h2>") && d.includes('class="nodes"'), "pipeline node strip section");
  assert.ok(d.includes("<details class=\"node\">"), "nodes are native <details> (no JS)");
  assert.ok(d.includes("Triage") && d.includes("clearly an app refinement"), "triage node shows reason");
  assert.ok(d.includes("0.91"), "triage confidence surfaced");
  assert.ok(d.includes("hexagonal kept"), "gate verdict reason surfaced");
  assert.ok(d.includes("app-refinement/2026-06-19-x"), "executor branch surfaced");
  assert.ok(d.includes("Executor · native"), "executor node labeled by id");
  assert.ok(d.includes("<h2>Timeline</h2>"), "history relabeled Timeline");
});

test("renderReference renders the glossary + the live pipelines", () => {
  const html = renderReference([FLOW_PROFILE, { ...FLOW_PROFILE, pipeline: "project-ideation", label: "Project Ideation", executors: ["spec"], executorMode: "none", enabled: false }]);
  // glossary canon terms
  for (const term of ["Pipeline", "Step", "Stage", "State", "Executor", "Schedule", "Domain", "Gate", "Triage", "Flow board"]) {
    assert.ok(html.includes(term), `glossary has ${term}`);
  }
  assert.ok(html.includes("<h2>Glossary</h2>") && html.includes("<h2>Live pipelines</h2>"), "two sections");
  // live pipelines: label, gates in order, executor, enabled
  assert.ok(html.includes("App Refinement") && html.includes("Project Ideation"), "pipeline labels");
  assert.ok(html.includes("chestertons-fence") && html.includes("premortem"), "gates listed");
  assert.ok(html.includes(">native<") || html.includes("native"), "executor listed");
  assert.ok(html.includes("class=\"active\">Reference"), "Reference nav active");
});

function prReviewFixture(over: Partial<PrReview> = {}): PrReview {
  return {
    id: "my-goal/fix-x", goal: "my-goal", cardSlug: "fix-x", title: "Fix the X bug",
    repo: "eriqueo/x", branch: "nightly/2026-06-19-fix-x", base: "main",
    prUrl: "https://github.com/eriqueo/x/pull/42", prNumber: 42, reviewedAt: "2026-06-19T09:00:00Z",
    verdict: "merge-ready", mergeable: true, diffstat: { files: 2, insertions: 10, deletions: 3 },
    commits: ["fix the bug"], whatWasDone: "fixed it", whatItMeans: "no more crash",
    recommendation: "merge it", risks: ["touches the hot path"], status: "needs-you", reportRelPath: null,
    ...over,
  };
}

test("renderReviews groups PrReviews into status lanes; empty state otherwise", () => {
  const reviews = [
    prReviewFixture(),
    prReviewFixture({ id: "g/2", title: "Merged change", status: "merged", verdict: "merge-ready", prUrl: "https://github.com/eriqueo/x/pull/43" }),
    prReviewFixture({ id: "g/3", title: "Rejected change", status: "rejected", verdict: "reject", prUrl: null }),
  ];
  const html = renderReviews(reviews);
  assert.ok(html.includes('class="board"'), "lane board");
  assert.ok(html.includes(">Needs You ") && html.includes(">Merged ") && html.includes(">Rejected "), "status lanes");
  assert.ok(html.includes("Fix the X bug") && html.includes("Merged change") && html.includes("Rejected change"), "cards");
  assert.ok(html.includes("eriqueo/x"), "repo shown");
  assert.ok(html.includes("merge it"), "recommendation shown");
  assert.ok(html.includes('href="https://github.com/eriqueo/x/pull/42"'), "PR link");
  assert.ok(html.includes("touches the hot path"), "risk shown");
  assert.ok(html.includes("no PR yet"), "null prUrl → no-PR placeholder");
  assert.ok(html.includes("class=\"active\">Reviews"), "Reviews nav active");

  const empty = renderReviews([]);
  assert.ok(empty.includes("no PR reviews yet"), "empty state");
});

// ── idea → spec → build assembly line: build pipeline, chaining, two kanbans ──

import { PipelineCatalog } from "../src/pipelines/catalog.js";
import { fileURLToPath } from "node:url";

const REAL_PIPELINES_DIR = fileURLToPath(new URL("../../../pipelines", import.meta.url));

test("build.yaml loads via the catalog as a terminal (next-less) pipeline; project-ideation has next: build", () => {
  const cat = new PipelineCatalog({ dir: REAL_PIPELINES_DIR });
  const build = cat.get("build");
  assert.ok(build, "build pipeline on disk");
  assert.equal(build!.executorMode, "write");
  assert.deepEqual(build!.executors, ["native"]);
  // Single admission-gates gate since 5a5880ae: the spec was already vetted in
  // ideation, so build only asks "safe to run unattended?" before native execute.
  assert.deepEqual(build!.gates, ["admission-gates"]);
  assert.equal(build!.next, undefined, "build is terminal — no next");
  assert.equal(build!.defaultTraits?.mode, "brownfield");

  const ideation = cat.get("project-ideation");
  assert.ok(ideation, "project-ideation on disk");
  assert.equal(ideation!.next, "build", "project-ideation chains to build");
});

test("a passed spec item with chain:true auto-creates a successor build item via runItem", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass"), chain: true });
  try {
    const shell = createShell(cfg);
    const ready: Item = {
      id: "chain1", pipeline: "project-ideation", step: "stepwise-refinement", state: "pending",
      payload: { title: "an idea to chain", input: "an engine that refines ideas into specs", repo: "/tmp/target-app", domain: "datax" },
      chain: true, history: [],
    };
    await shell.store.save(ready);
    await shell.runItem("chain1");

    // The spec passed, and because chain:true + pipeline.next=build, a successor
    // build item was created and kicked.
    const parent = (await shell.store.load("chain1"))!;
    assert.equal(parent.state, "passed", "spec pass");

    const successor = (await shell.store.load("chain1-build"))!;
    assert.ok(successor, "successor build item created with deterministic id");
    assert.equal(successor.pipeline, "build");
    const sp = successor.payload as Record<string, any>;
    assert.equal(sp.parent, "chain1", "carries parent id");
    assert.ok(sp.spec && sp.spec.goal, "carries the developed spec");
    assert.equal(sp.repo, "/tmp/target-app", "carries the target repo");
    // build is native → the board ran its gates then spooled (running), or it
    // parked at a gate; either way it exists as a build item with the spec.
    assert.ok(["running", "pending", "parked", "passed", "failed"].includes(successor.state));
  } finally {
    cleanup();
  }
});

test("a passed spec item with chain off (default) does NOT create a successor", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass"), chain: true });
  try {
    const shell = createShell(cfg);
    const ready: Item = {
      id: "nochain1", pipeline: "project-ideation", step: "stepwise-refinement", state: "pending",
      payload: { title: "no auto", input: "an engine that refines ideas into specs", repo: "/tmp/x" },
      history: [], // chain undefined → off
    };
    await shell.store.save(ready);
    await shell.runItem("nochain1");
    assert.equal((await shell.store.load("nochain1"))!.state, "passed");
    assert.equal(await shell.store.load("nochain1-build"), null, "no successor without chain:true");
  } finally {
    cleanup();
  }
});

test("POST /build one-shot creates the successor build item from a completed spec", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass"), chain: true });
  try {
    const shell = createShell(cfg);
    const done: Item = {
      id: "os1", pipeline: "project-ideation", step: "premortem", state: "passed",
      payload: {
        title: "a finished spec", repo: "/tmp/build-target",
        executorResult: { outcome: "succeeded", verdict: "spec-written", detail: "wrote spec",
          output: { specPath: "/specs/os1.md", spec: { goal: "Build it", steps: ["s1"], deliverable: "a module" } } },
      },
      history: [],
    };
    await shell.store.save(done);
    await shell.buildNow("os1"); // the POST /build handler calls this
    const successor = (await shell.store.load("os1-build"))!;
    assert.ok(successor, "one-shot build created the successor");
    assert.equal(successor.pipeline, "build");
    assert.equal((successor.payload as Record<string, any>).repo, "/tmp/build-target");

    // buildNow on an item with no spec is a no-op (nothing to build).
    await shell.store.save({ id: "os2", pipeline: "project-ideation", step: "premortem", state: "passed", payload: { title: "nospec" }, history: [] });
    await shell.buildNow("os2");
    assert.equal(await shell.store.load("os2-build"), null, "no spec → no successor");
  } finally {
    cleanup();
  }
});

test("/chain toggles item.chain on and off", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    await shell.store.save({ id: "tog1", pipeline: "project-ideation", step: "premortem", state: "passed", payload: { title: "x" }, history: [] });
    await shell.setChain("tog1", true);
    assert.equal((await shell.store.load("tog1"))!.chain, true);
    await shell.setChain("tog1", false);
    assert.equal((await shell.store.load("tog1"))!.chain, false);
  } finally {
    cleanup();
  }
});

test("renderProjectDetail on a done spec shows 'build this' + the auto-build toggle", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executorMode: "none",
      executors: ["spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26", next: "build" },
  ];
  const done: Item = {
    id: "bd1", pipeline: "project-ideation", step: "premortem", state: "passed",
    payload: {
      title: "a finished idea",
      executorResult: { outcome: "succeeded", verdict: "spec-written", detail: "wrote spec",
        output: { specPath: "/specs/bd1.md", spec: { goal: "Ship it", steps: ["x"], deliverable: "a module" } } },
    },
    history: [{ step: "spec", status: "passed", at: "t1" }],
  };
  const d = renderProjectDetail(done, profiles, profiles);
  assert.ok(d.includes('action="/build"') && d.includes("build this"), "one-shot build button");
  assert.ok(d.includes('action="/chain"'), "auto-build toggle form");
  assert.ok(d.includes("turn auto-build ON"), "toggle reads ON when chain is off");
  assert.ok(d.includes("stops at the spec for review"), "toggle hint explains off/on");

  // With chain already on, the toggle offers to turn it off.
  const on = renderProjectDetail({ ...done, chain: true }, profiles, profiles);
  assert.ok(on.includes("turn auto-build OFF"), "toggle reads OFF when chain is on");

  // A pipeline with no `next` (no spec successor) shows neither.
  const noNext = renderProjectDetail(done, [{ ...profiles[0], next: undefined }], [{ ...profiles[0], next: undefined }]);
  assert.ok(!noNext.includes('action="/build"'), "no build button when the pipeline has no next");
});

test("renderBoard is attention-first: Needs You, Active, Hopper sections", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "premortem"], executorMode: "none", executors: ["spec"],
      enabled: true, llmProvider: "claude-cli", color: "#a3be8c" },
  ];
  const ideas: Item[] = [
    { id: "i1", pipeline: UNTRIAGED, stage: "captured", state: "parked", payload: { title: "raw idea", input: "raw idea" }, history: [] },
  ];
  const projects: Item[] = [
    { id: "p1", pipeline: "project-ideation", step: "premortem", state: "pending", payload: { title: "a project" }, history: [] },
  ];
  const html = renderBoard(ideas, projects, profiles, profiles, DOMAINS);
  assert.ok(html.includes("Needs You"), "Needs You section header comes first");
  assert.ok(html.indexOf("Needs You") < html.indexOf("Hopper — ideas"), "attention before hopper");
  assert.ok(html.includes("Hopper — ideas"), "Hopper section header");
  assert.ok(html.includes("raw idea"), "an idea card in the Hopper");
  assert.ok(html.includes("a project") && html.includes('href="/project/p1"'), "a pending project in Active");
  assert.ok(html.includes('action="/intake"'), "intake box at the top");
  assert.ok(html.includes(">Captured<"), "Hopper stage lanes");
  assert.ok(html.includes(">In Pipeline<"), "Active status lanes");
  assert.ok(html.includes('method="get" action="/"'), "GET filter bar present");
});

test("renderBoard routes parked/failed to Needs You and folds passed into Recently done", () => {
  const profiles = [
    { pipeline: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "premortem"], executorMode: "none", executors: ["spec"],
      enabled: true, llmProvider: "claude-cli", color: "#a3be8c" },
  ];
  const projects: Item[] = [
    { id: "pk", pipeline: "project-ideation", step: "premortem", state: "parked", parkedReason: "needs a decision",
      payload: { title: "parked thing" }, history: [{ step: "premortem", status: "parked", at: "2026-07-01T00:00:00Z" }] },
    { id: "dn", pipeline: "project-ideation", step: "spec", state: "passed",
      payload: { title: "done thing" }, history: [{ step: "spec", status: "passed", at: "2026-07-14T00:00:00Z" }] },
  ];
  const html = renderBoard([], projects, profiles, profiles, DOMAINS, { archivedCount: 5, now: Date.parse("2026-07-15T00:00:00Z") });
  const needsYou = html.indexOf("Needs You");
  const doneFold = html.indexOf("Recently done");
  assert.ok(needsYou >= 0 && doneFold >= 0, "both sections render");
  const parkedPos = html.indexOf("parked thing");
  const donePos = html.indexOf("done thing");
  assert.ok(needsYou < parkedPos && parkedPos < doneFold, "parked card sits in Needs You");
  assert.ok(donePos > doneFold, "passed card sits in the folded done shelf");
  assert.ok(html.includes("5 archived"), "archived count links to /finished");
  assert.ok(html.includes(">1d<") || html.includes("1d</span>"), "age badge rendered from history");
});

// ── archive sweep: the exit ramp for passed engine items ──

test("sweepArchive: aged-out passed items archive, fresh ones stay, manual move revives", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const old: Item = {
      id: "old1", pipeline: "project-ideation", step: "spec", state: "passed",
      payload: { title: "old passed" },
      history: [{ step: "spec", status: "passed", at: "2026-06-01T00:00:00Z" }], // 14d before fixedClock
    };
    const fresh: Item = {
      id: "fresh1", pipeline: "project-ideation", step: "spec", state: "passed",
      payload: { title: "fresh passed" },
      history: [{ step: "spec", status: "passed", at: "2026-06-14T00:00:00Z" }], // 1d before fixedClock
    };
    await shell.store.save(old);
    await shell.store.save(fresh);
    await shell.sweepArchive();

    const oldAfter = (await shell.store.load("old1"))!;
    const freshAfter = (await shell.store.load("fresh1"))!;
    assert.equal(oldAfter.archived, true, "aged-out passed item archived");
    assert.ok(oldAfter.archivedAt, "archive stamped");
    assert.notEqual(freshAfter.archived, true, "fresh passed item stays on the board");

    // A manual lane move revives the archived item.
    await shell.setStatus("old1", "pending");
    const revived = (await shell.store.load("old1"))!;
    assert.notEqual(revived.archived, true, "status move clears archived");
    assert.equal(revived.archivedAt, undefined);
  } finally {
    cleanup();
  }
});

test("sweepArchive: a chain-complete parent archives regardless of age", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { chain: true });
  try {
    const shell = createShell(cfg);
    const parent: Item = {
      id: "par1", pipeline: "project-ideation", step: "spec", state: "passed",
      payload: { title: "spec done" },
      history: [{ step: "spec", status: "passed", at: "2026-06-14T23:00:00Z" }], // fresh
    };
    const successor: Item = {
      id: "par1-build", pipeline: "build", step: "admission-gates", state: "pending",
      payload: { title: "build: spec done", parent: "par1" },
      history: [{ step: "triage", status: "entered", at: "2026-06-14T23:30:00Z" }],
    };
    await shell.store.save(parent);
    await shell.store.save(successor);
    await shell.sweepArchive();

    assert.equal((await shell.store.load("par1"))!.archived, true, "parent archived: successor carries the story");
    assert.notEqual((await shell.store.load("par1-build"))!.archived, true, "successor stays");
  } finally {
    cleanup();
  }
});

test("chainTo inherits the parent's classified domain (successors are not Misc)", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"), { runLlm: runStub("pass"), chain: true });
  try {
    // A domains registry whose "kidpix" domain matches the parent's input prefix.
    const domainsFile = join(cfg.capsPath, "..", "domains.yaml");
    writeFileSync(domainsFile, `domains:\n  - key: kidpix\n    label: KidPix\n    color: "#b16286"\n    match: [kidpix]\nfallback:\n  key: misc\n  label: Misc\n  color: "#a7aaad"\n  match: []\n`);
    const shell = createShell({ ...cfg, domainsFile });
    const ready: Item = {
      id: "kp1", pipeline: "project-ideation", step: "stepwise-refinement", state: "pending",
      payload: { title: "kidpix: funny sounds", input: "kidpix: funny custom sounds for erasers" },
      chain: true, history: [],
    };
    await shell.store.save(ready);
    await shell.runItem("kp1");

    const successor = (await shell.store.load("kp1-build"))!;
    assert.ok(successor, "successor chained");
    const pl = successor.payload as { domain?: string };
    assert.equal(pl.domain, "kidpix", "successor carries the parent's classified domain");
  } finally {
    cleanup();
  }
});
