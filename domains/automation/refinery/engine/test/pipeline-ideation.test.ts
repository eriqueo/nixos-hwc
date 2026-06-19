import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, rmSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { parsePipeline } from "../src/pipeline.js";
import { gateList } from "../src/gates/index.js";
import { LlmPort } from "../src/gates/llm-port.js";
import { makeSpecExecutor, isSpecComplete } from "../src/executors/spec.js";
import { MarkdownItemStore } from "../src/stores/markdown-store.js";
import { runPipelineOnce } from "../src/cli/run-once.js";
import { Item } from "../src/contracts.js";
import { fixedClock, resetClock } from "./helpers.js";

// The actual pipeline (cwd-independent path from the compiled test file).
const PIPELINE_PATH = fileURLToPath(
  new URL("../../../pipelines/project-ideation.yaml", import.meta.url),
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

test("project-ideation profile validates against the slice-03 Pipeline schema", () => {
  const pipeline = parsePipeline(readFileSync(PIPELINE_PATH, "utf8"));
  assert.equal(pipeline.pipeline, "project-ideation");
  assert.deepEqual(pipeline.gates, ["stepwise-refinement", "principles-create", "premortem"]);
  assert.deepEqual(pipeline.executors, ["spec"]);
});

test("MarkdownItemStore round-trips an item losslessly", async () => {
  const dir = tmp("refinery-store-");
  try {
    const store = new MarkdownItemStore(dir);
    const item: Item = {
      id: "round-trip",
      pipeline: "project-ideation",
      step: "premortem",
      state: "passed",
      payload: { input: "an idea", title: "an idea", traits: { mode: "greenfield" } },
      history: [{ step: "stepwise-refinement", status: "passed", at: "2026-06-15T00:00:00Z" }],
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

test("end-to-end: a sentence runs through the pipeline and produces a complete spec", async () => {
  resetClock();
  const storeDir = tmp("refinery-items-");
  const scratchDir = tmp("refinery-specs-");
  try {
    const llm = stubLlm("pass");
    const pipeline = parsePipeline(readFileSync(PIPELINE_PATH, "utf8"));
    const store = new MarkdownItemStore(storeDir);
    const result = await runPipelineOnce(
      { id: "demo-item", input: "an engine that refines ideas into specs" },
      {
        pipeline,
        gates: gateList(llm),
        integrate: makeSpecExecutor({ scratchDir }, llm),
        store,
        clock: fixedClock,
      },
    );

    assert.equal(result.parked, false);
    assert.deepEqual(result.ran, ["stepwise-refinement", "principles-create", "premortem"]);
    assert.equal(result.item.step, "premortem");
    assert.equal(result.item.state, "passed");

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
    assert.equal(reloaded!.history.at(-1)!.step, "spec");

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
    const pipeline = parsePipeline(readFileSync(PIPELINE_PATH, "utf8"));
    const result = await runPipelineOnce(
      { id: "parked-item", input: "a half-baked idea" },
      {
        pipeline,
        gates: gateList(llm),
        integrate: makeSpecExecutor({ scratchDir }, llm),
        store: new MarkdownItemStore(storeDir),
        clock: fixedClock,
      },
    );
    assert.equal(result.parked, true);
    assert.equal(result.integrated, null);
    assert.deepEqual(result.ran, ["stepwise-refinement"]);
    assert.equal(result.item.state, "parked");
    assert.equal(existsSync(join(scratchDir, "parked-item-spec.md")), false);
  } finally {
    rmSync(storeDir, { recursive: true, force: true });
    rmSync(scratchDir, { recursive: true, force: true });
  }
});
