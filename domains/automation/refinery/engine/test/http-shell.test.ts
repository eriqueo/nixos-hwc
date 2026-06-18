import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createShell, HttpShellConfig } from "../src/shells/http.js";
import { renderGauntlet, renderHopperPage, renderNightly, renderSr, renderSrDetail, renderProjectDetail } from "../src/shells/render.js";
import { LlmPort } from "../src/gates/llm-port.js";
import { Item } from "../src/contracts.js";
import { UNTRIAGED } from "../src/triage.js";
import { fixedClock } from "./helpers.js";

function setup(
  triageLlm: LlmPort,
  opts: { runLlm?: LlmPort; autoRun?: boolean } = {},
): { cfg: HttpShellConfig; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "refinery-shell-"));
  const profilesDir = join(root, "profiles");
  mkdirSync(profilesDir, { recursive: true });
  writeFileSync(
    join(profilesDir, "project-ideation.yaml"),
    `genre: project-ideation\nlabel: Project Ideation\nsource: http-intake\ngates:\n  - stepwise-refinement\n  - principles-create\n  - premortem\nexecuteMode: none\neffectors:\n  - write-spec\n${opts.autoRun ? "autoRun: true\n" : ""}`,
  );
  return {
    cfg: {
      port: 0,
      itemsDir: join(root, "items"),
      profilesDir,
      profileStatePath: join(root, "state.json"),
      capsPath: join(root, "caps.json"),
      scratchDir: join(root, "specs"),
      triageProvider: "claude-cli",
      runNowSpoolDir: join(root, "run-now"),
      srRunNowSpoolDir: join(root, "sr-run-now"),
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

const triageStub = (genre: string, confidence = 0.9): LlmPort => ({
  async complete() {
    return JSON.stringify({ genre, confidence, reason: "stub" });
  },
});

test("intake triages a sentence into a profile item at its first gate", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    await shell.intake("an engine that refines ideas");
    const items = await shell.store.list();
    assert.equal(items.length, 1);
    assert.equal(items[0].genre, "project-ideation");
    assert.equal(items[0].phase, "stepwise-refinement");
    assert.equal(items[0].phaseStatus, "pending");
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
    assert.equal(item.genre, UNTRIAGED);
    assert.equal(item.phaseStatus, "parked");
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
    assert.equal(item.genre, "untriaged");
    assert.equal(item.phaseStatus, "parked");
  } finally {
    cleanup();
  }
});

test("amend re-arms a parked item with the note recorded", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const parked: Item = {
      id: "p1", genre: "project-ideation", phase: "premortem", phaseStatus: "parked",
      parkedReason: "needs a call", payload: { title: "p1" }, history: [],
    };
    await shell.store.save(parked);
    await shell.amend("p1", "here is the answer");
    const item = (await shell.store.load("p1"))!;
    assert.equal(item.phaseStatus, "pending");
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
      id: "r1", genre: "project-ideation", phase: "premortem", phaseStatus: "parked",
      payload: { title: "r1" }, history: [],
    };
    await shell.store.save(item);
    await shell.doRewind("r1", "stepwise-refinement", "found an upstream problem");
    const back = (await shell.store.load("r1"))!;
    assert.equal(back.phase, "stepwise-refinement");
    assert.equal(back.phaseStatus, "pending");
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
      id: "n1", genre: "project-ideation", phase: "premortem", phaseStatus: "pending",
      payload: { title: "n1" }, history: [],
    };
    await shell.store.save(p);
    await shell.setNightly("n1", true);
    let item = (await shell.store.load("n1"))!;
    assert.equal(item.nightly, true);
    assert.equal(item.nightlyPriority, 0);
    await shell.bumpNightly("n1", "up");
    item = (await shell.store.load("n1"))!;
    assert.equal(item.nightlyPriority, 1);
    await shell.setNightly("n1", false);
    assert.equal((await shell.store.load("n1"))!.nightly, false);
  } finally {
    cleanup();
  }
});

test("promote turns an untriaged idea into a project at its profile's first phase", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const idea: Item = {
      id: "idea1", genre: UNTRIAGED, phase: "triage", phaseStatus: "parked",
      parkedReason: "no clear genre", payload: { title: "raw" }, history: [],
    };
    await shell.store.save(idea);
    await shell.promote("idea1", "project-ideation");
    const item = (await shell.store.load("idea1"))!;
    assert.equal(item.genre, "project-ideation");
    assert.equal(item.phase, "stepwise-refinement");
    assert.equal(item.phaseStatus, "pending");
    assert.equal(item.history.at(-1)!.status, "entered");
  } finally {
    cleanup();
  }
});

test("renderSr lists SR investigations linking to their REPORT + has a max cap form", () => {
  const profiles = [
    { genre: "datax-sr", label: "DataX SR", source: "sr", gates: ["premortem"], executeMode: "read-only",
      effectors: ["execute"], enabled: true, llmProvider: "claude-cli", color: "#83a598" },
  ];
  const srs: Item[] = [
    { id: "sr:2026-06-12-abc", genre: "datax-sr", phase: "investigated", phaseStatus: "passed",
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
    id: "sr:2026-06-12-abc", genre: "datax-sr", phase: "investigated", phaseStatus: "passed",
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
      id: "del1", genre: "project-ideation", phase: "premortem", phaseStatus: "passed",
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
    { genre: "nightly-build", label: "Nightly Builds", source: "vault", gates: ["stepwise-refinement"],
      executeMode: "write", effectors: ["execute"], enabled: true, llmProvider: "claude-cli", color: "#fe8019" },
  ];
  const project: Item = {
    id: "e1", genre: "nightly-build", phase: "premortem", phaseStatus: "passed",
    payload: { title: "editable" }, history: [],
  };
  assert.ok(renderProjectDetail(project, profiles, profiles).includes('action="/delete"'));

  const mirror: Item = {
    id: "nb:goal/01-x", genre: "nightly-build", phase: "queued", phaseStatus: "pending",
    payload: { title: "mirror card", readonly: true, run: "runs/2026-06-15-x/", pr: "branch x" }, history: [], nightly: true,
  };
  const d = renderProjectDetail(mirror, profiles, profiles);
  assert.ok(d.includes("read-only"));
  assert.ok(d.includes("runs/2026-06-15-x/"));
  assert.ok(!d.includes('action="/delete"'), "mirror cards aren't deletable");
  assert.ok(!d.includes('action="/amend"'), "mirror cards aren't editable");
});

test("renderProjectDetail shows actions + nightly toggle; renderNightly is a status-lane kanban", () => {
  const profiles = [
    { genre: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executeMode: "none",
      effectors: ["write-spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26" },
  ];
  const parked: Item = {
    id: "d1", genre: "project-ideation", phase: "premortem", phaseStatus: "parked",
    parkedReason: "needs a call", payload: { title: "a project" }, history: [], nightly: true,
  };
  const detail = renderProjectDetail(parked, profiles, profiles);
  assert.ok(detail.includes('action="/amend"'));
  assert.ok(detail.includes('action="/rewind"'));
  assert.ok(detail.includes('action="/nightly/toggle"'));
  assert.ok(detail.includes("remove from nightly"), "nightly already on → offers removal");
  assert.ok(detail.includes('value="stepwise-refinement"'));

  const idea: Item = {
    id: "d2", genre: UNTRIAGED, phase: "triage", phaseStatus: "parked",
    payload: { title: "raw idea" }, history: [],
  };
  assert.ok(renderProjectDetail(idea, profiles, profiles).includes('action="/promote"'), "ideas can be promoted");

  // A read-only nightly-build mirror card carries its vault-backed queue control inline.
  const mirror: Item = {
    id: "nb:goal/01-x", genre: "nightly-build", phase: "1/3 steps", phaseStatus: "parked",
    payload: { title: "mirror card", readonly: true, source: "nightly-builds project",
      stepsDone: 1, stepsTotal: 3, queuedCount: 0, mode: "nightly", nextStatus: "draft" },
    history: [], nightly: true,
  };
  const n = renderNightly([parked, mirror], 1, profiles, profiles);
  assert.ok(n.includes('class="board"'), "nightly is a status-lane kanban");
  assert.ok(n.includes("a project") && n.includes('href="/project/d1"'), "project as a click-through card");
  assert.ok(n.includes('action="/card/queue"') && n.includes("✅ queue"), "mirror card queues inline");
  assert.ok(n.includes('formaction="/card/run-now"'), "mirror card runs inline");
  assert.ok(n.includes('action="/nightly/config"'));
});

test("renderGauntlet colors a parked project and links to detail; renderHopperPage shows intake", () => {
  const profiles = [
    { genre: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executeMode: "none",
      effectors: ["write-spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26" },
  ];
  const parked: Item[] = [
    { id: "x", genre: "project-ideation", phase: "premortem", phaseStatus: "parked",
      parkedReason: "needs a call", payload: { title: "a project" }, history: [] },
  ];
  const g = renderGauntlet(parked, profiles, profiles);
  assert.ok(g.includes("a project"));
  assert.ok(g.includes("#b8bb26"), "card tinted by profile color");
  assert.ok(g.includes('href="/project/x"'), "title links to its detail page");
  // Inline per-card controls (SR2-style quick actions): a status/lane dropdown,
  // a run button, and a delete — acting directly on the board.
  assert.ok(g.includes('action="/status"') && g.includes('name="status"'), "lane dropdown on the card");
  assert.ok(g.includes('action="/run"'), "run button on the card");
  assert.ok(g.includes('action="/delete"'), "delete on the card");
  assert.ok(g.includes('name="back" value="/"'), "actions redirect back to the board");
  assert.ok(!g.includes('action="/amend"'), "amend (needs a note) stays on the detail page");
  // Intake lives on the Hopper page, over untriaged ideas; each idea promotes inline.
  const idea: Item[] = [
    { id: "i", genre: UNTRIAGED, phase: "triage", phaseStatus: "parked",
      payload: { title: "a raw idea" }, history: [] },
  ];
  const h = renderHopperPage(idea, profiles, profiles);
  assert.ok(h.includes('action="/intake"'));
  assert.ok(h.includes("a raw idea"));
  assert.ok(h.includes('action="/promote"') && h.includes('value="project-ideation"'), "inline promote dropdown");
});

test("setStatus moves an engine item to another lane (manual board override)", async () => {
  const { cfg, cleanup } = setup(triageStub("project-ideation"));
  try {
    const shell = createShell(cfg);
    const p: Item = {
      id: "mv1", genre: "project-ideation", phase: "premortem", phaseStatus: "pending",
      payload: { title: "movable" }, history: [],
    };
    await shell.store.save(p);
    await shell.setStatus("mv1", "parked");
    const moved = await shell.store.load("mv1");
    assert.equal(moved!.phaseStatus, "parked");
    assert.equal(moved!.history.at(-1)!.note, "status set on board");
    // invalid status is ignored (no throw, no change)
    await shell.setStatus("mv1", "bogus");
    assert.equal((await shell.store.load("mv1"))!.phaseStatus, "parked");
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
    assert.equal(item!.phase, "premortem");
    assert.equal(item!.phaseStatus, "passed");
    assert.equal(item!.history.at(-1)!.phase, "write-spec");
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
    assert.equal((await shell.store.load(id))!.phaseStatus, "passed");
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
    assert.equal((await shell.store.list())[0]!.phaseStatus, "passed", "auto-ran to completion");
  } finally {
    cleanup();
  }
});

test("renderProjectDetail shows a Run button for a pending engine item; running hides it", () => {
  const profiles = [
    { genre: "project-ideation", label: "Project Ideation", source: "http-intake",
      gates: ["stepwise-refinement", "principles-create", "premortem"], executeMode: "none",
      effectors: ["write-spec"], enabled: true, llmProvider: "claude-cli", color: "#b8bb26" },
  ];
  const pending: Item = {
    id: "r1", genre: "project-ideation", phase: "stepwise-refinement", phaseStatus: "pending",
    payload: { title: "an idea", input: "an idea" }, history: [],
  };
  const d = renderProjectDetail(pending, profiles, profiles);
  assert.ok(d.includes('action="/run"'), "pending engine item exposes the Run form");
  assert.ok(d.includes("run pipeline now"));

  const running = renderProjectDetail({ ...pending, phaseStatus: "running" }, profiles, profiles);
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
    id: "sr:2026-06-15-abc", genre: "datax-sr", phase: "done", phaseStatus: "passed",
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
