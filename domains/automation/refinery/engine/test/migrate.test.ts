import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { MarkdownItemStore } from "../src/stores/markdown-store.js";

// The read-old/write-new migration shim (markdown-store.migrateItemJson):
// a pre-rename .md file carries the legacy field names (genre/phase/phaseStatus/
// nightly) in its canonical JSON block. load() must normalize them to the new
// Item shape (pipeline/step|stage/state/schedule) before ItemSchema.parse, so
// existing on-disk state survives the rename. We write a legacy file by hand
// (the only way old data exists) and assert load() upgrades it.

/** Write a .md file with an OLD-format canonical JSON block, like a pre-rename save(). */
function writeLegacy(dir: string, id: string, json: Record<string, unknown>): void {
  const text = [
    "---",
    `id: ${id}`,
    "---",
    "",
    "<!-- canonical item (do not hand-edit) -->",
    "```json",
    JSON.stringify(json, null, 2),
    "```",
    "",
  ].join("\n");
  writeFileSync(join(dir, `${id}.md`), text);
}

test("MarkdownItemStore.load migrates a legacy triaged item (genre/phase/phaseStatus/nightly → pipeline/step/state/schedule)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "refinery-migrate-"));
  try {
    writeLegacy(dir, "legacy-proj", {
      id: "legacy-proj",
      genre: "project-ideation",
      phase: "premortem",
      phaseStatus: "parked",
      payload: { title: "an old project" },
      history: [{ phase: "stepwise-refinement", status: "passed", at: "2026-06-15T00:00:00Z" }],
      nightly: true,
      nightlyPriority: 3,
    });

    const store = new MarkdownItemStore(dir);
    const item = await store.load("legacy-proj");
    assert.ok(item);
    // identity + position renamed
    assert.equal(item!.pipeline, "project-ideation");
    assert.equal(item!.step, "premortem"); // triaged → step (not stage)
    assert.equal(item!.stage, undefined);
    assert.equal(item!.state, "parked");
    // scheduling: nightly:true → schedule:"nightly"
    assert.equal(item!.schedule, "nightly");
    assert.equal(item!.schedulePriority, 3);
    // history entry phase → step
    assert.equal(item!.history[0]!.step, "stepwise-refinement");
    // legacy keys are gone (didn't leak through)
    assert.equal((item as Record<string, unknown>).genre, undefined);
    assert.equal((item as Record<string, unknown>).phaseStatus, undefined);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("MarkdownItemStore.load migrates a legacy untriaged idea (phase:'captured' → stage, not step)", async () => {
  const dir = mkdtempSync(join(tmpdir(), "refinery-migrate-"));
  try {
    writeLegacy(dir, "brain-abc", {
      id: "brain-abc",
      genre: "untriaged",
      phase: "captured",
      phaseStatus: "parked",
      payload: { title: "a raw idea", source: "brain idea" },
      history: [],
      nightly: false,
    });

    const store = new MarkdownItemStore(dir);
    const item = await store.load("brain-abc");
    assert.ok(item);
    assert.equal(item!.pipeline, "untriaged");
    // an untriaged idea's hopper maturation phase maps to `stage`, NOT `step`
    assert.equal(item!.stage, "captured");
    assert.equal(item!.step, undefined);
    assert.equal(item!.state, "parked");
    // nightly:false → schedule:"now"
    assert.equal(item!.schedule, "now");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
