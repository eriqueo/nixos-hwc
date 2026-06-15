import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createShell, HttpShellConfig } from "../src/shells/http.js";
import { renderGauntlet, renderHopperPage } from "../src/shells/render.js";
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

test("renderGauntlet colors a parked project and shows amend/rewind; renderHopperPage shows intake", () => {
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
  assert.ok(g.includes('action="/amend"'));
  assert.ok(g.includes('action="/rewind"'));
  assert.ok(g.includes('value="stepwise-refinement"'), "rewind targets = earlier phases");
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
