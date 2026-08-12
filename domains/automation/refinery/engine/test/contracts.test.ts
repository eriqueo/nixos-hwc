import { test } from "node:test";
import assert from "node:assert/strict";
import {
  appendItemEvent,
  compactEvents,
  currentJudgment,
  Item,
  ItemEvent,
  ItemSchema,
  ITEM_EVENT_CAP,
  judgmentsFor,
  nextJudgmentVersion,
  outcomeOf,
  withEvidence,
} from "../src/contracts.js";

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

// ─── Item events: the versioned judgment trail (case-ledger law 2) ───

const judgment = (step: string, verdict: string, at: string, version?: number): ItemEvent => ({
  type: "judgment", at, actor: step, step, verdict, decision: "pass", version,
});

test("pre-event items parse unchanged (old persisted files)", () => {
  const result = ItemSchema.safeParse(base);
  assert.equal(result.success, true);
  assert.equal(result.success && result.data.events, undefined);
});

test("appendItemEvent stamps monotonically increasing per-step versions", () => {
  let item = ItemSchema.parse(base) as Item;
  assert.equal(nextJudgmentVersion(item, "spec"), 1);
  item = appendItemEvent(item, judgment("spec", "ok", "t1"));
  item = appendItemEvent(item, judgment("spec", "better", "t2"));
  item = appendItemEvent(item, judgment("other", "unrelated", "t3"));
  assert.deepEqual(item.events!.filter((e) => e.step === "spec").map((e) => e.version), [1, 2]);
  // Versions are per-step: another gate's trail starts at 1, not at 3.
  assert.deepEqual(item.events!.filter((e) => e.step === "other").map((e) => e.version), [1]);
  assert.equal(nextJudgmentVersion(item, "spec"), 3);
});

test("judgmentsFor folds events oldest-first and currentJudgment is the newest", () => {
  let item = ItemSchema.parse(base) as Item;
  item = appendItemEvent(item, judgment("spec", "first", "t1"));
  item = appendItemEvent(item, judgment("spec", "second", "t2"));
  const trail = judgmentsFor(item, "spec");
  assert.deepEqual(trail.map((j) => j.verdict), ["first", "second"]);
  assert.deepEqual(trail.map((j) => j.version), [1, 2]);
  assert.equal(trail.every((j) => j.source === "event"), true);
  assert.equal(currentJudgment(item, "spec")!.verdict, "second");
});

test("judgmentsFor falls back to payload.verdicts when an item has no events", () => {
  // Exactly the shape every item written before this release carries: a single
  // mutable slot, no event log. It must NOT read back as empty history.
  const legacy = ItemSchema.parse({
    ...base,
    payload: { verdicts: { spec: { decision: "park", reason: "needs a human call", output: { asks: ["pick a db"] } } } },
  }) as Item;
  const trail = judgmentsFor(legacy, "spec");
  assert.equal(trail.length, 1);
  assert.equal(trail[0]!.source, "legacy");
  assert.equal(trail[0]!.version, 1);
  assert.equal(trail[0]!.decision, "park");
  assert.equal(trail[0]!.verdict, "needs a human call");
  assert.deepEqual((trail[0]!.output as { asks: string[] }).asks, ["pick a db"]);
  // A step with neither events nor a legacy slot is genuinely empty.
  assert.deepEqual(judgmentsFor(legacy, "nothing-here"), []);
});

test("events win over the legacy slot once one exists (write-both, read events-first)", () => {
  let item = ItemSchema.parse({
    ...base,
    payload: { verdicts: { spec: { decision: "park", reason: "stale slot", output: null } } },
  }) as Item;
  item = appendItemEvent(item, judgment("spec", "fresh verdict", "t1"));
  const trail = judgmentsFor(item, "spec");
  assert.equal(trail.length, 1, "the legacy slot is not concatenated onto the event trail");
  assert.equal(trail[0]!.source, "event");
  assert.equal(trail[0]!.verdict, "fresh verdict");
});

test("compactEvents caps the log, shedding oldest NON-judgment events first", () => {
  const events: ItemEvent[] = [];
  // 10 actions then 35 judgments = 45, five over the cap.
  for (let i = 0; i < 10; i++) {
    events.push({ type: "action", at: `a${i}`, actor: "human", note: `a${i}` });
  }
  for (let i = 0; i < 35; i++) events.push(judgment("spec", `v${i}`, `j${i}`, i + 1));

  const kept = compactEvents(events);
  assert.equal(kept.length, ITEM_EVENT_CAP);
  assert.equal(kept.filter((e) => e.type === "judgment").length, 35, "no judgment was shed");
  assert.equal(kept.filter((e) => e.type === "action").length, 5, "the 5 oldest actions went");
  assert.equal(kept[0]!.note, "a5", "the survivors are the NEWEST actions");
});

test("compactEvents sheds oldest judgments only when the log is all judgments", () => {
  const events: ItemEvent[] = [];
  for (let i = 0; i < ITEM_EVENT_CAP + 3; i++) events.push(judgment("spec", `v${i}`, `j${i}`, i + 1));
  const kept = compactEvents(events);
  assert.equal(kept.length, ITEM_EVENT_CAP);
  assert.equal(kept[0]!.version, 4, "the three oldest judgments were shed");
  assert.equal(kept[kept.length - 1]!.version, ITEM_EVENT_CAP + 3, "the newest is always kept");
});

test("appendItemEvent keeps an item at the cap without unbounded growth", () => {
  let item = ItemSchema.parse(base) as Item;
  for (let i = 0; i < ITEM_EVENT_CAP * 2; i++) {
    item = appendItemEvent(item, judgment("spec", `v${i}`, `j${i}`));
  }
  assert.equal(item.events!.length, ITEM_EVENT_CAP);
  // Versions keep climbing even though early events were compacted away — the
  // counter reads the surviving max, so it never reissues a version.
  assert.equal(item.events![item.events!.length - 1]!.version, ITEM_EVENT_CAP * 2);
});
