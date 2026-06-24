import { test } from "node:test";
import assert from "node:assert/strict";
import { Pipeline } from "../src/contracts.js";
import { InMemoryItemStore } from "../src/store-memory.js";
import { rewind, runPass } from "../src/runner.js";
import { fixedClock, makeItem, resetClock, stubGate } from "./helpers.js";

const pipeline: Pipeline = {
  pipeline: "test-pipeline",
  source: "inline://test",
  gates: ["g1", "g2", "g3"],
  executorMode: "sync",
  executors: [],
};

test("forward-advance: passes through all gates and ends past last gate", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();
  const gates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2" }),
    stubGate({ id: "g3" }),
  ];
  const result = await runPass(item, pipeline, gates, { store, clock: fixedClock });
  assert.deepEqual(result.ran, ["g1", "g2", "g3"]);
  assert.equal(result.item.step, "g3");
  assert.equal(result.item.state, "passed");
  assert.equal(result.stoppedBy, undefined);
  assert.equal(result.item.history.length, 3);
  assert.deepEqual(result.item.history.map((h) => [h.step, h.status]), [
    ["g1", "passed"],
    ["g2", "passed"],
    ["g3", "passed"],
  ]);
  const saved = await store.load("item-1");
  assert.ok(saved);
  assert.equal(saved!.state, "passed");
});

test("park-on-fail: stops at first parking gate with parkedReason + history entry", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();
  const gates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2", decision: "park", verdictLabel: "needs-input" }),
    stubGate({ id: "g3" }),
  ];
  const result = await runPass(item, pipeline, gates, { store, clock: fixedClock });
  assert.deepEqual(result.ran, ["g1", "g2"]);
  assert.deepEqual(result.stoppedBy, { step: "g2", reason: "parked" });
  assert.equal(result.item.step, "g2");
  assert.equal(result.item.state, "parked");
  assert.equal(result.item.parkedReason, "needs-input");
  const last = result.item.history.at(-1)!;
  assert.equal(last.step, "g2");
  assert.equal(last.status, "parked");
  assert.equal(last.note, "needs-input");
});

test("fail-stop: failed gate records 'failed' status + reason", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();
  const gates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2", decision: "fail", verdictLabel: "hard-error" }),
    stubGate({ id: "g3" }),
  ];
  const result = await runPass(item, pipeline, gates, { store, clock: fixedClock });
  assert.deepEqual(result.stoppedBy, { step: "g2", reason: "failed" });
  assert.equal(result.item.state, "failed");
  assert.equal(result.item.parkedReason, "hard-error");
});

test("park-and-resume: a parked item resumes from its parked step on next pass", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();

  // Pass 1: park at g2.
  const firstGates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2", decision: "park", verdictLabel: "wait" }),
    stubGate({ id: "g3" }),
  ];
  const first = await runPass(item, pipeline, firstGates, { store, clock: fixedClock });
  assert.equal(first.item.step, "g2");
  assert.equal(first.item.state, "parked");

  // Pass 2: g2 now passes; g1 must NOT be re-run.
  const ranIds: string[] = [];
  const secondGates = [
    stubGate({ id: "g1", onRun: (i) => ranIds.push("g1@" + i.id) }),
    stubGate({ id: "g2", onRun: (i) => ranIds.push("g2@" + i.id) }),
    stubGate({ id: "g3", onRun: (i) => ranIds.push("g3@" + i.id) }),
  ];
  const second = await runPass(first.item, pipeline, secondGates, {
    store,
    clock: fixedClock,
  });
  assert.deepEqual(second.ran, ["g2", "g3"]);
  assert.deepEqual(ranIds, ["g2@item-1", "g3@item-1"]);
  assert.equal(second.item.step, "g3");
  assert.equal(second.item.state, "passed");
});

test("applies()===false gates are skipped (never run, no history entry)", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();
  let g2Ran = false;
  const gates = [
    stubGate({ id: "g1" }),
    stubGate({
      id: "g2",
      applies: () => false,
      onRun: () => {
        g2Ran = true;
      },
    }),
    stubGate({ id: "g3" }),
  ];
  const result = await runPass(item, pipeline, gates, { store, clock: fixedClock });
  assert.equal(g2Ran, false);
  assert.deepEqual(result.ran, ["g1", "g3"]);
  assert.equal(
    result.item.history.find((h) => h.step === "g2"),
    undefined,
  );
  assert.equal(result.item.step, "g3");
  assert.equal(result.item.state, "passed");
});

test("rewind moves backward, sets pending, appends a 'rewound' history entry; re-runs on next pass", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();
  const gates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2" }),
    stubGate({ id: "g3" }),
  ];
  const first = await runPass(item, pipeline, gates, { store, clock: fixedClock });
  assert.equal(first.item.step, "g3");

  const rewound = rewind(first.item, "g1", "found a problem upstream", {
    clock: fixedClock,
  });
  assert.equal(rewound.step, "g1");
  assert.equal(rewound.state, "pending");
  const last = rewound.history.at(-1)!;
  assert.equal(last.step, "g1");
  assert.equal(last.status, "rewound");
  assert.equal(last.note, "found a problem upstream");

  // Replaying re-runs from g1.
  const ranIds: string[] = [];
  const replayGates = [
    stubGate({ id: "g1", onRun: () => ranIds.push("g1") }),
    stubGate({ id: "g2", onRun: () => ranIds.push("g2") }),
    stubGate({ id: "g3", onRun: () => ranIds.push("g3") }),
  ];
  const replay = await runPass(rewound, pipeline, replayGates, {
    store,
    clock: fixedClock,
  });
  assert.deepEqual(ranIds, ["g1", "g2", "g3"]);
  assert.deepEqual(replay.ran, ["g1", "g2", "g3"]);
});

test("rewind throws UnknownStepError when toPhase isn't in the pipeline (validated)", () => {
  resetClock();
  const item = makeItem({ step: "g3", state: "passed" });
  assert.throws(
    () => rewind(item, "ghost", "typo", { clock: fixedClock, pipeline }),
    /step not present in pipeline gates: ghost/,
  );
  // Without a pipeline, rewind stays permissive (runPass guards on next pass).
  const lenient = rewind(item, "ghost", "deferred", { clock: fixedClock });
  assert.equal(lenient.step, "ghost");
});

test("runPass throws UnknownGateError when pipeline references a missing gate", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();
  const gates = [stubGate({ id: "g1" })]; // missing g2/g3
  await assert.rejects(
    () => runPass(item, pipeline, gates, { store, clock: fixedClock }),
    /unregistered gate: g2/,
  );
});

test("runPass throws UnknownStepError when item.phase isn't in pipeline", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem({ step: "ghost" });
  const gates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2" }),
    stubGate({ id: "g3" }),
  ];
  await assert.rejects(
    () => runPass(item, pipeline, gates, { store, clock: fixedClock }),
    /step not present in pipeline gates: ghost/,
  );
});
