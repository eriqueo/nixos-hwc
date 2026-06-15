import { test } from "node:test";
import assert from "node:assert/strict";
import { Profile } from "../src/contracts.js";
import { InMemoryItemStore } from "../src/store-memory.js";
import { rewind, runPass } from "../src/runner.js";
import { fixedClock, makeItem, resetClock, stubGate } from "./helpers.js";

const profile: Profile = {
  genre: "test-genre",
  source: "inline://test",
  gates: ["g1", "g2", "g3"],
  executeMode: "sync",
  effectors: [],
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
  const result = await runPass(item, profile, gates, { store, clock: fixedClock });
  assert.deepEqual(result.ran, ["g1", "g2", "g3"]);
  assert.equal(result.item.stage, "g3");
  assert.equal(result.item.stageStatus, "passed");
  assert.equal(result.stoppedBy, undefined);
  assert.equal(result.item.history.length, 3);
  assert.deepEqual(result.item.history.map((h) => [h.stage, h.status]), [
    ["g1", "passed"],
    ["g2", "passed"],
    ["g3", "passed"],
  ]);
  const saved = await store.load("item-1");
  assert.ok(saved);
  assert.equal(saved!.stageStatus, "passed");
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
  const result = await runPass(item, profile, gates, { store, clock: fixedClock });
  assert.deepEqual(result.ran, ["g1", "g2"]);
  assert.deepEqual(result.stoppedBy, { stage: "g2", reason: "parked" });
  assert.equal(result.item.stage, "g2");
  assert.equal(result.item.stageStatus, "parked");
  assert.equal(result.item.parkedReason, "needs-input");
  const last = result.item.history.at(-1)!;
  assert.equal(last.stage, "g2");
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
  const result = await runPass(item, profile, gates, { store, clock: fixedClock });
  assert.deepEqual(result.stoppedBy, { stage: "g2", reason: "failed" });
  assert.equal(result.item.stageStatus, "failed");
  assert.equal(result.item.parkedReason, "hard-error");
});

test("park-and-resume: a parked item resumes from its parked stage on next pass", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();

  // Pass 1: park at g2.
  const firstGates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2", decision: "park", verdictLabel: "wait" }),
    stubGate({ id: "g3" }),
  ];
  const first = await runPass(item, profile, firstGates, { store, clock: fixedClock });
  assert.equal(first.item.stage, "g2");
  assert.equal(first.item.stageStatus, "parked");

  // Pass 2: g2 now passes; g1 must NOT be re-run.
  const ranIds: string[] = [];
  const secondGates = [
    stubGate({ id: "g1", onRun: (i) => ranIds.push("g1@" + i.id) }),
    stubGate({ id: "g2", onRun: (i) => ranIds.push("g2@" + i.id) }),
    stubGate({ id: "g3", onRun: (i) => ranIds.push("g3@" + i.id) }),
  ];
  const second = await runPass(first.item, profile, secondGates, {
    store,
    clock: fixedClock,
  });
  assert.deepEqual(second.ran, ["g2", "g3"]);
  assert.deepEqual(ranIds, ["g2@item-1", "g3@item-1"]);
  assert.equal(second.item.stage, "g3");
  assert.equal(second.item.stageStatus, "passed");
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
  const result = await runPass(item, profile, gates, { store, clock: fixedClock });
  assert.equal(g2Ran, false);
  assert.deepEqual(result.ran, ["g1", "g3"]);
  assert.equal(
    result.item.history.find((h) => h.stage === "g2"),
    undefined,
  );
  assert.equal(result.item.stage, "g3");
  assert.equal(result.item.stageStatus, "passed");
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
  const first = await runPass(item, profile, gates, { store, clock: fixedClock });
  assert.equal(first.item.stage, "g3");

  const rewound = rewind(first.item, "g1", "found a problem upstream", {
    clock: fixedClock,
  });
  assert.equal(rewound.stage, "g1");
  assert.equal(rewound.stageStatus, "pending");
  const last = rewound.history.at(-1)!;
  assert.equal(last.stage, "g1");
  assert.equal(last.status, "rewound");
  assert.equal(last.note, "found a problem upstream");

  // Replaying re-runs from g1.
  const ranIds: string[] = [];
  const replayGates = [
    stubGate({ id: "g1", onRun: () => ranIds.push("g1") }),
    stubGate({ id: "g2", onRun: () => ranIds.push("g2") }),
    stubGate({ id: "g3", onRun: () => ranIds.push("g3") }),
  ];
  const replay = await runPass(rewound, profile, replayGates, {
    store,
    clock: fixedClock,
  });
  assert.deepEqual(ranIds, ["g1", "g2", "g3"]);
  assert.deepEqual(replay.ran, ["g1", "g2", "g3"]);
});

test("rewind throws UnknownStageError when toStage isn't in the profile (validated)", () => {
  resetClock();
  const item = makeItem({ stage: "g3", stageStatus: "passed" });
  assert.throws(
    () => rewind(item, "ghost", "typo", { clock: fixedClock, profile }),
    /stage not present in profile gates: ghost/,
  );
  // Without a profile, rewind stays permissive (runPass guards on next pass).
  const lenient = rewind(item, "ghost", "deferred", { clock: fixedClock });
  assert.equal(lenient.stage, "ghost");
});

test("runPass throws UnknownGateError when profile references a missing gate", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem();
  const gates = [stubGate({ id: "g1" })]; // missing g2/g3
  await assert.rejects(
    () => runPass(item, profile, gates, { store, clock: fixedClock }),
    /unregistered gate: g2/,
  );
});

test("runPass throws UnknownStageError when item.stage isn't in profile", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const item = makeItem({ stage: "ghost" });
  const gates = [
    stubGate({ id: "g1" }),
    stubGate({ id: "g2" }),
    stubGate({ id: "g3" }),
  ];
  await assert.rejects(
    () => runPass(item, profile, gates, { store, clock: fixedClock }),
    /stage not present in profile gates: ghost/,
  );
});
