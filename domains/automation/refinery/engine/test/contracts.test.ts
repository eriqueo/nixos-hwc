import { test } from "node:test";
import assert from "node:assert/strict";
import { Item, ItemSchema, outcomeOf, withEvidence } from "../src/contracts.js";

test("ItemSchema accepts a well-formed item", () => {
  const result = ItemSchema.safeParse({
    id: "x",
    pipeline: "leads",
    step: "intake",
    state: "pending",
    payload: { any: "shape" },
    history: [],
  });
  assert.equal(result.success, true);
});

test("ItemSchema rejects unknown state", () => {
  const result = ItemSchema.safeParse({
    id: "x",
    pipeline: "leads",
    step: "intake",
    state: "wat",
    payload: {},
    history: [],
  });
  assert.equal(result.success, false);
});

// ── outcome + evidence (case-ledger fields) ──────────────────────────────────

const base = {
  id: "x",
  pipeline: "leads",
  step: "intake",
  state: "pending",
  payload: {},
  history: [],
};

test("pre-outcome/pre-evidence items parse unchanged (old persisted files)", () => {
  // `base` has neither field — the exact shape every pre-change .md carries.
  const result = ItemSchema.safeParse(base);
  assert.equal(result.success, true);
  assert.equal(result.success && result.data.outcome, undefined);
  assert.equal(result.success && result.data.evidence, undefined);
});

test("ItemSchema accepts the closed outcome vocabulary and rejects strays", () => {
  for (const outcome of ["need_met", "wont_do", "superseded", "unknown"]) {
    assert.equal(ItemSchema.safeParse({ ...base, outcome }).success, true, outcome);
  }
  assert.equal(ItemSchema.safeParse({ ...base, outcome: "passed" }).success, false,
    "execution states are NOT outcomes — the vocabularies must not blur");
});

test("ItemSchema accepts typed evidence and rejects unknown kinds", () => {
  const good = { ...base, evidence: [{ kind: "pr", ref: "https://github.test/pr/1", at: "2026-08-10T00:00:00Z" }] };
  assert.equal(ItemSchema.safeParse(good).success, true);
  const badKind = { ...base, evidence: [{ kind: "vibes", ref: "x", at: "t" }] };
  assert.equal(ItemSchema.safeParse(badKind).success, false);
});

test("outcomeOf defaults an absent outcome to unknown", () => {
  const item = ItemSchema.parse(base) as Item;
  assert.equal(outcomeOf(item), "unknown");
  assert.equal(outcomeOf({ ...item, outcome: "need_met" }), "need_met");
});

test("withEvidence appends and dedupes by (kind, ref) — producers stay idempotent", () => {
  const item = ItemSchema.parse(base) as Item;
  const once = withEvidence(item, [{ kind: "branch", ref: "b1", at: "t1" }]);
  assert.deepEqual(once.evidence, [{ kind: "branch", ref: "b1", at: "t1" }]);
  // same ref again (even with a different timestamp) → no duplicate
  const twice = withEvidence(once, [
    { kind: "branch", ref: "b1", at: "t2" },
    { kind: "pr", ref: "b1", at: "t2" }, // same ref, different kind → distinct join
  ]);
  assert.deepEqual(twice.evidence, [
    { kind: "branch", ref: "b1", at: "t1" },
    { kind: "pr", ref: "b1", at: "t2" },
  ]);
  // nothing to add → the item is returned unchanged (no gratuitous copy)
  assert.equal(withEvidence(twice, [{ kind: "pr", ref: "b1", at: "t9" }]), twice);
});
