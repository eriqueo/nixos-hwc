import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createShell, HttpShellConfig } from "../src/shells/http.js";
import { renderGauntlet, renderHopperPage, renderNightly, renderSr, renderProjectDetail } from "../src/shells/render.js";
import { LlmPort } from "../src/gates/llm-port.js";
import { Item } from "../src/contracts.js";
import { UNTRIAGED } from "../src/triage.js";
import { fixedClock } from "./helpers.js";

function setup(triageLlm: LlmPort): { cfg: HttpShellConfig; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "refinery-shell-"));
  const profilesDir = join(root, "profiles");
  mkdirSync(profilesDir, { recursive: true });
  writeFileSync(
    join(profilesDir, "project-ideation.yaml"),
    "genre: project-ideation\nlabel: Project Ideation\nsource: http-intake\ngates:\n  - stepwise-refinement\n  - principles-create\n  - premortem\nexecuteMode: none\neffectors:\n  - write-spec\n",
  );
  return {
    cfg: {
      port: 0,
      itemsDir: join(root, "items"),
      profilesDir,
      profileStatePath: join(root, "state.json"),
      capsPath: join(root, "caps.json"),
      triageProvider: "claude-cli",
      clock: fixedClock,
      triageLlm,
    },
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
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
      payload: { title: "Customer X cannot sync", srStatus: "engaged", run: "investigations/2026-06-12-abc/", hasReport: true, readonly: true, source: "sr_gauntlet investigation" }, history: [] },
  ];
  const html = renderSr(srs, 5, profiles);
  assert.ok(html.includes("Customer X cannot sync"));
  assert.ok(html.includes('href="/report/sr:2026-06-12-abc"'), "card links straight to the REPORT");
  assert.ok(html.includes('action="/sr/config"'), "has the max-per-run cap form");
  assert.ok(html.includes('value="5"'));
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

test("renderProjectDetail shows actions + nightly toggle; renderNightly highlights the top N", () => {
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

  const n = renderNightly([parked], 1, profiles);
  assert.ok(n.includes("tonight"));
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
  const g = renderGauntlet(parked, profiles);
  assert.ok(g.includes("a project"));
  assert.ok(g.includes("#b8bb26"), "card tinted by profile color");
  assert.ok(g.includes('href="/project/x"'), "card links to its detail page");
  assert.ok(!g.includes('action="/amend"'), "actions live on the detail page, not the card");
  assert.ok(!g.includes('action="/profiles/toggle"'), "no toggle — profiles are a legend");
  // Intake lives on the Hopper page, over untriaged ideas.
  const idea: Item[] = [
    { id: "i", genre: UNTRIAGED, phase: "triage", phaseStatus: "parked",
      payload: { title: "a raw idea" }, history: [] },
  ];
  const h = renderHopperPage(idea, profiles);
  assert.ok(h.includes('action="/intake"'));
  assert.ok(h.includes("a raw idea"));
});
