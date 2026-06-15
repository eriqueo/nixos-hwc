import { test } from "node:test";
import assert from "node:assert/strict";
import { loadManifest, parseManifest } from "../src/manifest.js";
import { InvalidManifestError } from "../src/errors.js";

const validYaml = `
genre: leads
source: file:///tmp/leads.yaml
gates:
  - intake
  - dedupe
  - score
executeMode: sync
effectors:
  - email-notifier
`;

test("parseManifest accepts a valid manifest", () => {
  const m = parseManifest(validYaml);
  assert.equal(m.genre, "leads");
  assert.deepEqual(m.gates, ["intake", "dedupe", "score"]);
  assert.equal(m.executeMode, "sync");
  assert.deepEqual(m.effectors, ["email-notifier"]);
});

test("parseManifest rejects manifest missing required fields with InvalidManifestError", () => {
  const bad = `
genre: leads
gates: []
executeMode: sync
effectors: []
`;
  let caught: unknown;
  try {
    parseManifest(bad);
  } catch (e) {
    caught = e;
  }
  assert.ok(caught instanceof InvalidManifestError, "expected InvalidManifestError");
  const err = caught as InvalidManifestError;
  assert.equal(err.code, "E_INVALID_MANIFEST");
  assert.ok(Array.isArray(err.issues));
  // 'source' missing AND gates min(1) violated.
  const issues = err.issues as Array<{ path: (string | number)[] }>;
  const paths = issues.map((i) => i.path.join("."));
  assert.ok(paths.includes("source"));
  assert.ok(paths.includes("gates"));
});

test("parseManifest rejects unparseable YAML with InvalidManifestError", () => {
  const bogus = "genre: [unterminated";
  assert.throws(() => parseManifest(bogus), (e: unknown) => {
    return (
      e instanceof InvalidManifestError &&
      (e as InvalidManifestError).code === "E_INVALID_MANIFEST"
    );
  });
});

test("loadManifest delegates to injected loader (hexagonal: no fs)", async () => {
  const m = await loadManifest("inline://leads", async (s) => {
    assert.equal(s, "inline://leads");
    return validYaml;
  });
  assert.equal(m.genre, "leads");
});
