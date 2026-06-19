import { test } from "node:test";
import assert from "node:assert/strict";
import { LlmPort } from "../src/gates/llm-port.js";
import { triageSentence, makeTriagedItem, UNTRIAGED } from "../src/triage.js";
import { fixedClock, resetClock } from "./helpers.js";

const OPTIONS = [
  { genre: "project-ideation", label: "Develop a raw idea into a spec" },
  { genre: "datax-sr", label: "Investigate a DataX support request" },
];

function stub(genre: string, confidence: number, reason = "matched"): LlmPort {
  return { async complete() { return JSON.stringify({ genre, confidence, reason }); } };
}

test("triage routes to a confidently-matched enabled genre", async () => {
  const d = await triageSentence("a new idea for a tool", OPTIONS, stub("project-ideation", 0.9));
  assert.equal(d.genre, "project-ideation");
  assert.equal(d.confidence, 0.9);
});

test("triage falls back to untriaged below the confidence threshold", async () => {
  const d = await triageSentence("???", OPTIONS, stub("project-ideation", 0.3));
  assert.equal(d.genre, UNTRIAGED);
});

test("triage falls back to untriaged when the model picks an unoffered genre", async () => {
  const d = await triageSentence("x", OPTIONS, stub("some-other-genre", 0.99));
  assert.equal(d.genre, UNTRIAGED);
});

test("makeTriagedItem: classified item starts pending at its first gate", () => {
  resetClock();
  const item = makeTriagedItem(
    "item-1",
    "build a thing",
    { genre: "project-ideation", confidence: 0.9, reason: "idea" },
    "stepwise-refinement",
    fixedClock,
  );
  assert.equal(item.genre, "project-ideation");
  assert.equal(item.phase, "stepwise-refinement");
  assert.equal(item.phaseStatus, "pending");
  assert.equal(item.history.at(-1)!.status, "entered");
});

test("makeTriagedItem: stamps the profile's defaultTraits (brownfield genre)", () => {
  resetClock();
  const item = makeTriagedItem(
    "item-3",
    "tighten the contracts in lead_scout",
    { genre: "app-refinement", confidence: 0.9, reason: "refactor existing app" },
    "chestertons-fence",
    fixedClock,
    { mode: "brownfield", touchesExistingCode: true, writeMode: true },
  );
  assert.deepEqual((item.payload as { traits: unknown }).traits, {
    mode: "brownfield",
    touchesExistingCode: true,
    writeMode: true,
  });
});

test("makeTriagedItem: falls back to greenfield traits when no defaultTraits given", () => {
  resetClock();
  const item = makeTriagedItem(
    "item-4",
    "build a new thing",
    { genre: "project-ideation", confidence: 0.9, reason: "idea" },
    "stepwise-refinement",
    fixedClock,
  );
  assert.deepEqual((item.payload as { traits: unknown }).traits, {
    mode: "greenfield",
    trivial: false,
    multiPart: true,
  });
});

test("makeTriagedItem: untriaged item parks at the triage phase for human routing", () => {
  resetClock();
  const item = makeTriagedItem(
    "item-2",
    "???",
    { genre: UNTRIAGED, confidence: 0.2, reason: "no clear genre" },
    "stepwise-refinement",
    fixedClock,
  );
  assert.equal(item.genre, UNTRIAGED);
  assert.equal(item.phase, "triage");
  assert.equal(item.phaseStatus, "parked");
  assert.match(item.parkedReason!, /no clear genre/);
});
