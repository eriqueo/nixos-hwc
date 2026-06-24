import { test } from "node:test";
import assert from "node:assert/strict";
import { runNative } from "../src/cli/run-native.js";
import { InMemoryItemStore } from "../src/store-memory.js";
import { Executor, ExecutorResult, Item, Pipeline } from "../src/contracts.js";
import { fixedClock, resetClock } from "./helpers.js";

const APP_REFINEMENT: Pipeline = {
  pipeline: "app-refinement",
  label: "App Refinement",
  source: "cli-input",
  gates: ["chestertons-fence", "premortem"],
  executorMode: "write",
  executors: ["native"],
};

const catalogStub = { get: (p: string) => (p === "app-refinement" ? APP_REFINEMENT : null) };

function appItem(): Item {
  return {
    id: "ar1",
    pipeline: "app-refinement",
    step: "premortem",
    state: "running",
    payload: { title: "refine some-app", input: "refine some-app", repo: "/tmp/some-app" },
    history: [{ step: "premortem", status: "passed", at: "t0" }],
  };
}

function stubExecutor(result: ExecutorResult): Executor {
  return { id: "native", async run() { return result; } };
}

const SUCCEEDED: ExecutorResult = {
  outcome: "succeeded", verdict: "success", reportPresent: true,
  branch: "app-refinement/2026-06-19-ar1", pristine: null, pushed: true,
  detail: "write run succeeded (verdict=success)", output: { files: 3 },
};

const FAILED: ExecutorResult = {
  outcome: "failed", verdict: null, reportPresent: false,
  branch: "app-refinement/2026-06-19-ar1", pristine: null, pushed: false,
  detail: "run failed: exit=1 timedOut=false verdict=none report=no", output: {},
};

test("runNative finalizes a clean native run → item passed with executorResult + history", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  await store.save(appItem());

  const done = await runNative(
    { id: "ar1" },
    { store, catalog: catalogStub, buildExecutor: () => stubExecutor(SUCCEEDED), clock: fixedClock },
  );

  assert.equal(done.state, "passed");
  const pl = done.payload as Record<string, any>;
  assert.deepEqual(pl.executorResult, SUCCEEDED, "full executor result persisted to payload");
  const last = done.history.at(-1)!;
  assert.equal(last.step, "native");
  assert.equal(last.status, "passed");
  assert.equal(last.note, SUCCEEDED.detail);
  // persisted, not just returned
  assert.equal((await store.load("ar1"))!.state, "passed");
});

test("runNative finalizes a failed native run → item failed", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  await store.save(appItem());

  const done = await runNative(
    { id: "ar1" },
    { store, catalog: catalogStub, buildExecutor: () => stubExecutor(FAILED), clock: fixedClock },
  );

  assert.equal(done.state, "failed");
  assert.equal((done.payload as Record<string, any>).executorResult.outcome, "failed");
  assert.equal(done.history.at(-1)!.status, "failed");
});

test("runNative throws on a missing item", async () => {
  const store = new InMemoryItemStore();
  await assert.rejects(
    () => runNative({ id: "nope" }, { store, catalog: catalogStub, buildExecutor: () => stubExecutor(SUCCEEDED) }),
    /no such item/,
  );
});

test("runNative throws on an unknown pipeline", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  await store.save({ ...appItem(), pipeline: "ghost" });
  await assert.rejects(
    () => runNative({ id: "ar1" }, { store, catalog: catalogStub, buildExecutor: () => stubExecutor(SUCCEEDED) }),
    /unknown pipeline/,
  );
});
