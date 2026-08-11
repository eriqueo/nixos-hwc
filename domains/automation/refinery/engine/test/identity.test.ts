// Content-derived identity (case-ledger law 1). Pure logic — no fs, no clock.
// The parity snapshots pin the exact djb2/normalize behavior that existed in
// sources/brain-ideas.ts BEFORE the extraction: existing on-disk `brain-<hash>`
// ids must keep resolving to the same items, so a drift in the hash function
// is a data-loss bug, not a refactor.

import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeText, djb2, contentId, intakeId, INTAKE_PREFIX } from "../src/identity.js";
import { ideaId, BRAIN_PREFIX } from "../src/sources/brain-ideas.js";

test("normalizeText drops the list dash, html comments, whitespace and case", () => {
  assert.equal(normalizeText("- An Idea  <!-- note -->"), "an idea");
  assert.equal(normalizeText("  plain sentence  "), "plain sentence");
  assert.equal(normalizeText("No-Dash stays"), "no-dash stays");
});

test("djb2 is deterministic and content-sensitive", () => {
  assert.equal(djb2("same input"), djb2("same input"));
  assert.notEqual(djb2("same input"), djb2("same input!"));
});

test("parity snapshot: ideaId is unchanged by the extraction (pre-refactor value)", () => {
  // Captured from the original brain-ideas.ts norm+hash before identity.ts
  // existed. If this fails, every persisted brain-* item orphans.
  assert.equal(ideaId("Keep this id stable across the refactor"), "brain-58rshw");
});

test("intakeId converges capitalization/whitespace drift onto one id", () => {
  const a = intakeId("  An Idea With Drift  ");
  const b = intakeId("an idea with drift");
  assert.equal(a, b);
  assert.equal(a, "in-m6aoto"); // snapshot: content-derived, never time-derived
  assert.ok(a.startsWith(INTAKE_PREFIX));
});

test("contentId namespaces the same text by prefix (brain- vs in-)", () => {
  const text = "one sentence, two intake paths";
  assert.equal(contentId(BRAIN_PREFIX, text), ideaId(text));
  assert.notEqual(contentId(BRAIN_PREFIX, text), contentId(INTAKE_PREFIX, text));
  // same hash token either way — only the namespace differs
  assert.equal(
    contentId(BRAIN_PREFIX, text).slice(BRAIN_PREFIX.length),
    contentId(INTAKE_PREFIX, text).slice(INTAKE_PREFIX.length),
  );
});
