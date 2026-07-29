// Tests for the six rev-3 backlog gates (2026-07-29): temporary-tracked (R5),
// bounded-capacity (13), effect-category (14), wired-or-labeled (R4),
// promotion-rule (10), session-output-routed (R8). Same conventions as
// gates.test.ts: stub LlmPort, applies()/decide() matrix, and each gate's own
// seed-red (a malformed verdict must fail loud, not pass silently).
import { test } from "node:test";
import assert from "node:assert/strict";
import { Item } from "../src/contracts.js";
import { InvalidGateVerdictError } from "../src/errors.js";
import { LlmPort } from "../src/gates/llm-port.js";
import {
  makeGateRegistry,
  makeTemporaryTrackedGate,
  makeBoundedCapacityGate,
  makeEffectCategoryGate,
  makeWiredOrLabeledGate,
  makePromotionRuleGate,
  makeSessionOutputRoutedGate,
} from "../src/gates/index.js";
import { makeItem } from "./helpers.js";

const NEW_FACTORIES = [
  ["temporary-tracked", makeTemporaryTrackedGate],
  ["bounded-capacity", makeBoundedCapacityGate],
  ["effect-category", makeEffectCategoryGate],
  ["wired-or-labeled", makeWiredOrLabeledGate],
  ["promotion-rule", makePromotionRuleGate],
  ["session-output-routed", makeSessionOutputRoutedGate],
] as const;

function stubLlm(decision: "pass" | "park" | "fail" = "pass", reason = "ok"): LlmPort {
  const body = { decision, reason, violations: decision === "pass" ? [] : ["one finding"] };
  return { async complete() { return JSON.stringify(body); } };
}

function rawLlm(raw: string): LlmPort {
  return { async complete() { return raw; } };
}

function itemWithTraits(traits: Record<string, unknown>): Item {
  return makeItem({ step: "temporary-tracked", payload: { traits } });
}

test("registry resolves all six governing gate ids", () => {
  const reg = makeGateRegistry(stubLlm());
  for (const [id] of NEW_FACTORIES) assert.ok(reg.has(id), `missing ${id}`);
});

test("applies(): trivial-scoped gates skip trivial items, fire otherwise", () => {
  const llm = stubLlm();
  const trivial = itemWithTraits({ trivial: true });
  const nonTrivial = itemWithTraits({ mode: "brownfield", trivial: false });
  const traitless = makeItem({ step: "x", payload: {} }); // safe-default: fires

  for (const make of [makeTemporaryTrackedGate, makeBoundedCapacityGate, makeEffectCategoryGate, makeWiredOrLabeledGate]) {
    assert.equal(make(llm).applies(trivial), false, `${make(llm).id} must skip trivial`);
    assert.equal(make(llm).applies(nonTrivial), true, `${make(llm).id} must fire on non-trivial`);
    assert.equal(make(llm).applies(traitless), true, `${make(llm).id} fires when traits absent`);
  }
});

test("applies(): write-mode-scoped gates need writeMode=true", () => {
  const llm = stubLlm();
  const write = itemWithTraits({ mode: "brownfield", writeMode: true });
  const readOnly = itemWithTraits({ mode: "brownfield", writeMode: false });
  const traitless = makeItem({ step: "x", payload: {} });

  for (const make of [makePromotionRuleGate, makeSessionOutputRoutedGate]) {
    assert.equal(make(llm).applies(write), true, `${make(llm).id} must fire in write mode`);
    assert.equal(make(llm).applies(readOnly), false, `${make(llm).id} must skip read-only`);
    assert.equal(make(llm).applies(traitless), false, `${make(llm).id} skips when traits absent`);
  }
});

test("run()/decide(): each gate maps pass, fail, and park verdicts", async () => {
  const item = itemWithTraits({ mode: "brownfield", writeMode: true, trivial: false });
  for (const [id, make] of NEW_FACTORIES) {
    const pass = await make(stubLlm("pass", "clean")).run(item);
    assert.equal(pass.verdict, "clean", id);
    assert.equal(make(stubLlm()).decide(pass), "pass", id);

    const fail = await make(stubLlm("fail", "violation found")).run(item);
    assert.equal(make(stubLlm()).decide(fail), "fail", id);

    const park = await make(stubLlm("park", "cannot assess from payload")).run(item);
    assert.equal(make(stubLlm()).decide(park), "park", id);
  }
});

test("seed-red: a malformed verdict throws InvalidGateVerdictError for every gate", async () => {
  const item = itemWithTraits({ mode: "brownfield", writeMode: true, trivial: false });
  for (const [id, make] of NEW_FACTORIES) {
    // non-JSON
    await assert.rejects(() => make(rawLlm("not json {")).run(item), InvalidGateVerdictError, id);
    // schema miss (missing violations array) — persists through the one
    // self-repair round, so it must fail loud
    const badShape = JSON.stringify({ decision: "pass", reason: "ok" });
    await assert.rejects(
      () => make(rawLlm(badShape)).run(item),
      (e: unknown) => e instanceof InvalidGateVerdictError && e.gateId === id,
      id,
    );
  }
});
