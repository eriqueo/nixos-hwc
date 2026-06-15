import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, rmSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { parseProfile } from "../src/profile.js";
import { gateList } from "../src/gates/index.js";
import { LlmPort } from "../src/gates/llm-port.js";
import { makeWriteSpecEffector, isSpecComplete } from "../src/effectors/write-spec.js";
import { MarkdownItemStore } from "../src/stores/markdown-store.js";
import { runGenreOnce } from "../src/cli/run-once.js";
import { Item } from "../src/contracts.js";
import { fixedClock, resetClock } from "./helpers.js";

// The actual genre profile (cwd-independent path from the compiled test file).
const PROFILE_PATH = fileURLToPath(
  new URL("../../../profiles/project-ideation.yaml", import.meta.url),
);

// One canned superset response satisfying every gate schema AND the spec schema.
function stubLlm(decision: "pass" | "park" = "pass"): LlmPort {
  const body = {
    decision,
    reason: decision === "pass" ? "ok" : "needs a human call",
    steps: ["scope the idea", "design the core"],
    violations: [],
    hypotheses: ["designed: deliberate"],
    references: [],
    killVectors: [{ vector: "scope creep", severity: "medium" }],
    gates: [{ n: 1, name: "unattended", pass: true }],
    goal: "Build a substance-agnostic refinement engine demo",
    principlesAudit: ["hexagonal: core has no IO", "contracts: Zod at boundaries"],
    deliverable: "a developed project spec markdown",
  };
  return { async complete() { return JSON.stringify(body); } };
}

function tmp(prefix: string): string {
  return mkdtempSync(join(tmpdir(), prefix));
}

test("project-ideation profile validates against the slice-03 Profile schema", () => {
  const profile = parseProfile(readFileSync(PROFILE_PATH, "utf8"));
  assert.equal(profile.genre, "project-ideation");
  assert.deepEqual(profile.gates, ["stepwise-refinement", "principles-create", "premortem"]);
  assert.deepEqual(profile.effectors, ["write-spec"]);
});

test("MarkdownItemStore round-trips an item losslessly", async () => {
  const dir = tmp("refinery-store-");
  try {
    const store = new MarkdownItemStore(dir);
    const item: Item = {
      id: "round-trip",
      genre: "project-ideation",
      phase: "premortem",
      phaseStatus: "passed",
      payload: { input: "an idea", title: "an idea", traits: { mode: "greenfield" } },
      history: [{ phase: "stepwise-refinement", status: "passed", at: "2026-06-15T00:00:00Z" }],
    };
    await store.save(item);
    const loaded = await store.load("round-trip");
    assert.deepEqual(loaded, item);
    const listed = await store.list();
    assert.equal(listed.length, 1);
    assert.deepEqual(listed[0], item);
    assert.equal(await store.load("nope"), null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("end-to-end: a sentence runs through the genre and produces a complete spec", async () => {
  resetClock();
  const storeDir = tmp("refinery-items-");
  const scratchDir = tmp("refinery-specs-");
  try {
    const llm = stubLlm("pass");
    const profile = parseProfile(readFileSync(PROFILE_PATH, "utf8"));
    const store = new MarkdownItemStore(storeDir);
    const result = await runGenreOnce(
      { id: "demo-item", input: "an engine that refines ideas into specs" },
      {
        profile,
        gates: gateList(llm),
        integrate: makeWriteSpecEffector({ scratchDir }, llm),
        store,
        clock: fixedClock,
      },
    );

    assert.equal(result.parked, false);
    assert.deepEqual(result.ran, ["stepwise-refinement", "principles-create", "premortem"]);
    assert.equal(result.item.phase, "premortem");
    assert.equal(result.item.phaseStatus, "passed");

    // integrate fired and wrote a complete spec
    assert.ok(result.integrated);
    assert.equal(result.integrated!.outcome, "succeeded");
    const specPath = (result.integrated!.output as { specPath: string }).specPath;
    assert.ok(existsSync(specPath));
    const spec = readFileSync(specPath, "utf8");
    assert.ok(isSpecComplete(spec), "spec must contain all required sections");
    assert.ok(spec.includes("## Premortem kill-vectors"));
    assert.ok(spec.includes("scope creep"));

    // the item was persisted with the integrate step in history
    const reloaded = await store.load("demo-item");
    assert.ok(reloaded);
    assert.equal(reloaded!.history.at(-1)!.phase, "write-spec");

    // no stray files beyond the one spec
    assert.deepEqual(readdirSync(scratchDir), ["demo-item-spec.md"]);
  } finally {
    rmSync(storeDir, { recursive: true, force: true });
    rmSync(scratchDir, { recursive: true, force: true });
  }
});

test("end-to-end: a parked gate stops the pass and integrate never runs", async () => {
  resetClock();
  const storeDir = tmp("refinery-items-");
  const scratchDir = tmp("refinery-specs-");
  try {
    const llm = stubLlm("park"); // first gate parks
    const profile = parseProfile(readFileSync(PROFILE_PATH, "utf8"));
    const result = await runGenreOnce(
      { id: "parked-item", input: "a half-baked idea" },
      {
        profile,
        gates: gateList(llm),
        integrate: makeWriteSpecEffector({ scratchDir }, llm),
        store: new MarkdownItemStore(storeDir),
        clock: fixedClock,
      },
    );
    assert.equal(result.parked, true);
    assert.equal(result.integrated, null);
    assert.deepEqual(result.ran, ["stepwise-refinement"]);
    assert.equal(result.item.phaseStatus, "parked");
    assert.equal(existsSync(join(scratchDir, "parked-item-spec.md")), false);
  } finally {
    rmSync(storeDir, { recursive: true, force: true });
    rmSync(scratchDir, { recursive: true, force: true });
  }
});
