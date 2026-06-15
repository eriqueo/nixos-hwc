import { test } from "node:test";
import assert from "node:assert/strict";
import { loadProfile, parseProfile } from "../src/profile.js";
import { InvalidProfileError } from "../src/errors.js";

const validYaml = `
genre: leads
label: Leads intake
source: file:///tmp/leads.yaml
gates:
  - intake
  - dedupe
  - score
executeMode: sync
effectors:
  - email-notifier
llmProvider: ollama
`;

test("parseProfile accepts a valid profile (incl. optional label/llmProvider)", () => {
  const p = parseProfile(validYaml);
  assert.equal(p.genre, "leads");
  assert.equal(p.label, "Leads intake");
  assert.deepEqual(p.gates, ["intake", "dedupe", "score"]);
  assert.equal(p.executeMode, "sync");
  assert.deepEqual(p.effectors, ["email-notifier"]);
  assert.equal(p.llmProvider, "ollama");
});

test("parseProfile rejects a profile missing required fields with InvalidProfileError", () => {
  const bad = `
genre: leads
gates: []
executeMode: sync
effectors: []
`;
  let caught: unknown;
  try {
    parseProfile(bad);
  } catch (e) {
    caught = e;
  }
  assert.ok(caught instanceof InvalidProfileError, "expected InvalidProfileError");
  const err = caught as InvalidProfileError;
  assert.equal(err.code, "E_INVALID_PROFILE");
  assert.ok(Array.isArray(err.issues));
  // 'source' missing AND gates min(1) violated.
  const issues = err.issues as Array<{ path: (string | number)[] }>;
  const paths = issues.map((i) => i.path.join("."));
  assert.ok(paths.includes("source"));
  assert.ok(paths.includes("gates"));
});

test("parseProfile rejects unparseable YAML with InvalidProfileError", () => {
  const bogus = "genre: [unterminated";
  assert.throws(() => parseProfile(bogus), (e: unknown) => {
    return (
      e instanceof InvalidProfileError &&
      (e as InvalidProfileError).code === "E_INVALID_PROFILE"
    );
  });
});

test("loadProfile delegates to injected loader (hexagonal: no fs)", async () => {
  const p = await loadProfile("inline://leads", async (s) => {
    assert.equal(s, "inline://leads");
    return validYaml;
  });
  assert.equal(p.genre, "leads");
});
