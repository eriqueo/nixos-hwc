import { test } from "node:test";
import assert from "node:assert/strict";
import { loadPipeline, parsePipeline } from "../src/pipeline.js";
import { InvalidPipelineError } from "../src/errors.js";

const validYaml = `
pipeline: leads
label: Leads intake
source: file:///tmp/leads.yaml
gates:
  - intake
  - dedupe
  - score
executorMode: sync
executors:
  - email-notifier
llmProvider: ollama
`;

test("parsePipeline accepts a valid pipeline (incl. optional label/llmProvider)", () => {
  const p = parsePipeline(validYaml);
  assert.equal(p.pipeline, "leads");
  assert.equal(p.label, "Leads intake");
  assert.deepEqual(p.gates, ["intake", "dedupe", "score"]);
  assert.equal(p.executorMode, "sync");
  assert.deepEqual(p.executors, ["email-notifier"]);
  assert.equal(p.llmProvider, "ollama");
});

test("parsePipeline rejects a pipeline missing required fields with InvalidPipelineError", () => {
  const bad = `
pipeline: leads
gates: []
executorMode: sync
executors: []
`;
  let caught: unknown;
  try {
    parsePipeline(bad);
  } catch (e) {
    caught = e;
  }
  assert.ok(caught instanceof InvalidPipelineError, "expected InvalidPipelineError");
  const err = caught as InvalidPipelineError;
  assert.equal(err.code, "E_INVALID_PIPELINE");
  assert.ok(Array.isArray(err.issues));
  // 'source' missing AND gates min(1) violated.
  const issues = err.issues as Array<{ path: (string | number)[] }>;
  const paths = issues.map((i) => i.path.join("."));
  assert.ok(paths.includes("source"));
  assert.ok(paths.includes("gates"));
});

test("parsePipeline rejects unparseable YAML with InvalidPipelineError", () => {
  const bogus = "pipeline: [unterminated";
  assert.throws(() => parsePipeline(bogus), (e: unknown) => {
    return (
      e instanceof InvalidPipelineError &&
      (e as InvalidPipelineError).code === "E_INVALID_PIPELINE"
    );
  });
});

test("loadPipeline delegates to injected loader (hexagonal: no fs)", async () => {
  const p = await loadPipeline("inline://leads", async (s) => {
    assert.equal(s, "inline://leads");
    return validYaml;
  });
  assert.equal(p.pipeline, "leads");
});
