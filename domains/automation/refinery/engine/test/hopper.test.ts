import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { readHopperCards, renderHopper } from "../src/shells/hopper.js";

test("readHopperCards reads NN- cards with status + title; skips non-cards", () => {
  const root = mkdtempSync(join(tmpdir(), "refinery-hopper-"));
  try {
    const goal = join(root, "_inbox", "nightly_builds", "refinery");
    mkdirSync(goal, { recursive: true });
    writeFileSync(join(goal, "01-x.md"), "---\ntitle: First\nstatus: done\n---\nbody");
    writeFileSync(join(goal, "_goal.md"), "---\ntitle: skip\n---\n");
    writeFileSync(join(goal, "notes.md"), "no prefix");
    const cards = readHopperCards(root);
    assert.equal(cards.length, 1);
    assert.equal(cards[0].title, "First");
    assert.equal(cards[0].status, "done");
    assert.ok(renderHopper(cards).includes("First"));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
