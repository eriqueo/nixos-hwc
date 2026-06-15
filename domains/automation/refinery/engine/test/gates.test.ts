import { test } from "node:test";
import assert from "node:assert/strict";
import { Item, Manifest } from "../src/contracts.js";
import { InMemoryItemStore } from "../src/store-memory.js";
import { runPass } from "../src/runner.js";
import { InvalidGateVerdictError } from "../src/errors.js";
import { LlmPort } from "../src/gates/llm-port.js";
import {
  gateList,
  makeGateRegistry,
  makeStepwiseRefinementGate,
  makePrinciplesCreateGate,
  makePrinciplesFixGate,
  makeChestertonsFenceGate,
  makeBlastRadiusGate,
  makePremortemGate,
  makeAdmissionGatesGate,
} from "../src/gates/index.js";
import { fixedClock, makeItem, resetClock } from "./helpers.js";

/** Stub LLM port returning one canned verdict valid for every gate's schema. */
function stubLlm(decision: "pass" | "park" | "fail" = "pass", reason = "ok"): LlmPort {
  const body = {
    decision,
    reason,
    steps: ["only step"],
    violations: [],
    hypotheses: ["designed: deliberate"],
    references: [],
    killVectors: [],
    gates: [{ n: 1, name: "unattended", pass: true }],
  };
  return { async complete() { return JSON.stringify(body); } };
}

function rawLlm(raw: string): LlmPort {
  return { async complete() { return raw; } };
}

function itemWithTraits(traits: Record<string, unknown>, stage = "stepwise-refinement"): Item {
  return makeItem({ stage, payload: { traits } });
}

const ALL_IDS = [
  "stepwise-refinement",
  "principles-create",
  "principles-fix",
  "chestertons-fence",
  "blast-radius",
  "premortem",
  "admission-gates",
];

test("registry resolves every canonical gate id", () => {
  const reg = makeGateRegistry(stubLlm());
  for (const id of ALL_IDS) assert.ok(reg.has(id), `missing ${id}`);
  assert.equal(reg.size, ALL_IDS.length);
  assert.deepEqual(gateList(stubLlm()).map((g) => g.id), ALL_IDS);
});

test("applies(): greenfield vs brownfield vs touches-existing vs trivial", () => {
  const llm = stubLlm();
  const greenfield = itemWithTraits({ mode: "greenfield", trivial: false });
  const brownfieldWrite = itemWithTraits({ mode: "brownfield", writeMode: true, trivial: false });
  const touches = itemWithTraits({ touchesExistingCode: true });
  const trivial = itemWithTraits({ trivial: true });

  // greenfield-only
  assert.equal(makePrinciplesCreateGate(llm).applies(greenfield), true);
  assert.equal(makePrinciplesCreateGate(llm).applies(brownfieldWrite), false);
  // brownfield-only
  assert.equal(makePrinciplesFixGate(llm).applies(brownfieldWrite), true);
  assert.equal(makePrinciplesFixGate(llm).applies(greenfield), false);
  // blast-radius needs brownfield AND write-mode
  assert.equal(makeBlastRadiusGate(llm).applies(brownfieldWrite), true);
  assert.equal(makeBlastRadiusGate(llm).applies(itemWithTraits({ mode: "brownfield" })), false);
  // chesterton fires only when touching existing code
  assert.equal(makeChestertonsFenceGate(llm).applies(touches), true);
  assert.equal(makeChestertonsFenceGate(llm).applies(greenfield), false);
  // stepwise + premortem skip trivial items
  assert.equal(makeStepwiseRefinementGate(llm).applies(trivial), false);
  assert.equal(makePremortemGate(llm).applies(trivial), false);
  assert.equal(makePremortemGate(llm).applies(greenfield), true);
  // admission-gates always applies
  assert.equal(makeAdmissionGatesGate(llm).applies(trivial), true);
});

test("decide() maps the validated verdict decision; run() surfaces the reason", async () => {
  const parkGate = makePremortemGate(stubLlm("park", "high-severity vector needs a call"));
  const item = itemWithTraits({ trivial: false });
  const verdict = await parkGate.run(item);
  assert.equal(verdict.verdict, "high-severity vector needs a call");
  assert.equal(parkGate.decide(verdict), "park");

  const failGate = makePrinciplesCreateGate(stubLlm("fail", "core imports a shell"));
  const fv = await failGate.run(itemWithTraits({ mode: "greenfield" }));
  assert.equal(failGate.decide(fv), "fail");
});

test("parseVerdict throws InvalidGateVerdictError on non-JSON and on schema mismatch", async () => {
  const notJson = makeStepwiseRefinementGate(rawLlm("not json {"));
  await assert.rejects(() => notJson.run(itemWithTraits({})), InvalidGateVerdictError);

  const badShape = makeStepwiseRefinementGate(rawLlm(JSON.stringify({ decision: "pass" }))); // no reason/steps
  await assert.rejects(
    () => badShape.run(itemWithTraits({})),
    (e: unknown) => e instanceof InvalidGateVerdictError && e.gateId === "stepwise-refinement",
  );
});

test("a manifest gate list composes through the slice-03 runner end-to-end", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  const llm = stubLlm("pass", "looks good");
  const gates = gateList(llm);
  const manifest: Manifest = {
    genre: "greenfield-test",
    source: "inline://gates-test",
    gates: ["principles-create", "premortem", "admission-gates"],
    executeMode: "sync",
    effectors: [],
  };
  const item = makeItem({
    stage: "principles-create",
    payload: { traits: { mode: "greenfield", trivial: false } },
  });

  const result = await runPass(item, manifest, gates, { store, clock: fixedClock });
  assert.deepEqual(result.ran, ["principles-create", "premortem", "admission-gates"]);
  assert.equal(result.item.stage, "admission-gates");
  assert.equal(result.item.stageStatus, "passed");
  assert.equal(result.stoppedBy, undefined);
});

test("end-to-end parks at the first gate that returns park, leaving later gates unrun", async () => {
  resetClock();
  const store = new InMemoryItemStore();
  // premortem parks; principles-create passes; admission-gates must not run.
  const passLlm = stubLlm("pass");
  const parkLlm = stubLlm("park", "needs a human call");
  const gates = [
    makePrinciplesCreateGate(passLlm),
    makePremortemGate(parkLlm),
    makeAdmissionGatesGate(passLlm),
  ];
  const manifest: Manifest = {
    genre: "greenfield-test",
    source: "inline://gates-test",
    gates: ["principles-create", "premortem", "admission-gates"],
    executeMode: "sync",
    effectors: [],
  };
  const item = makeItem({
    stage: "principles-create",
    payload: { traits: { mode: "greenfield", trivial: false } },
  });
  const result = await runPass(item, manifest, gates, { store, clock: fixedClock });
  assert.deepEqual(result.ran, ["principles-create", "premortem"]);
  assert.deepEqual(result.stoppedBy, { stage: "premortem", reason: "parked" });
  assert.equal(result.item.parkedReason, "needs a human call");
});
