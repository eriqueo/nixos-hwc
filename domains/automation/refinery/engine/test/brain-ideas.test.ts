import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  readBrainIdeas,
  syncBrainIdeas,
  promoteBrainIdea,
  removeBrainIdea,
  appendBrainIdea,
  ideaId,
  isBrainIdea,
} from "../src/sources/brain-ideas.js";
import { MarkdownItemStore } from "../src/stores/markdown-store.js";
import { UNTRIAGED } from "../src/triage.js";

const CLOCK = () => "2026-06-16T00:00:00Z";

function vault(ideas: string): { dir: string; ideasPath: string; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), "refinery-brain-"));
  const nb = join(dir, "_inbox", "nightly_builds");
  mkdirSync(nb, { recursive: true });
  const ideasPath = join(nb, "_ideas.md");
  writeFileSync(ideasPath, ideas);
  return { dir, ideasPath, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

const SAMPLE = `## new

## backlog
- build a spec engine
- wire up the hopper <!-- a comment -->

## drafted
- nightly idea gauntlet
`;

test("readBrainIdeas reads backlog + drafted (not new), stripping comments", () => {
  const v = vault(SAMPLE);
  try {
    const ideas = readBrainIdeas(v.dir);
    assert.deepEqual(
      ideas.map((i) => i.text).sort(),
      ["build a spec engine", "nightly idea gauntlet", "wire up the hopper"],
    );
    assert.deepEqual(
      ideas.map((i) => i.section).sort(),
      ["backlog", "backlog", "drafted"],
    );
  } finally {
    v.cleanup();
  }
});

test("syncBrainIdeas adds untriaged items and is idempotent", async () => {
  const v = vault(SAMPLE);
  try {
    const store = new MarkdownItemStore(join(v.dir, "items"));
    const first = await syncBrainIdeas(store, v.dir, CLOCK);
    assert.equal(first.added, 3);
    assert.equal(first.removed, 0);
    const items = await store.list();
    assert.equal(items.length, 3);
    assert.ok(items.every((i) => i.genre === UNTRIAGED && isBrainIdea(i)));

    // Re-running with no vault change is a pure no-op (deterministic ids).
    const second = await syncBrainIdeas(store, v.dir, CLOCK);
    assert.equal(second.added, 0);
    assert.equal(second.removed, 0);
  } finally {
    v.cleanup();
  }
});

test("an untriaged idea deleted from the vault is reconciled away", async () => {
  const v = vault(SAMPLE);
  try {
    const store = new MarkdownItemStore(join(v.dir, "items"));
    await syncBrainIdeas(store, v.dir, CLOCK);
    removeBrainIdea(v.dir, "wire up the hopper");
    const res = await syncBrainIdeas(store, v.dir, CLOCK);
    assert.equal(res.removed, 1);
    const left = (await store.list()).map((i) => (i.payload as { input: string }).input).sort();
    assert.deepEqual(left, ["build a spec engine", "nightly idea gauntlet"]);
  } finally {
    v.cleanup();
  }
});

test("a promoted idea survives a vault line removal and is never re-created", async () => {
  const v = vault(SAMPLE);
  try {
    const store = new MarkdownItemStore(join(v.dir, "items"));
    await syncBrainIdeas(store, v.dir, CLOCK);
    const id = ideaId("build a spec engine");

    // Promote it (genre leaves untriaged) + move the brain line to ## promoted.
    const item = await store.load(id);
    assert.ok(item);
    await store.save({ ...item!, genre: "project-ideation", phaseStatus: "pending" });
    promoteBrainIdea(v.dir, "build a spec engine", "project-ideation", CLOCK);

    // The line is gone from backlog → re-sync must NOT delete the project nor
    // re-add it as a fresh idea.
    const res = await syncBrainIdeas(store, v.dir, CLOCK);
    assert.equal(res.added, 0);
    assert.equal(res.removed, 0);
    const promoted = await store.load(id);
    assert.equal(promoted?.genre, "project-ideation");

    const md = readFileSync(v.ideasPath, "utf8");
    assert.ok(/## promoted/.test(md), "a ## promoted section was created");
    assert.ok(/build a spec engine\s+<!-- → project-ideation 2026-06-16 -->/.test(md));
    // The idea is gone from the backlog section specifically (it now lives only
    // under ## promoted). Scope the check to backlog → next header.
    const backlog = /## backlog\n([\s\S]*?)\n## /.exec(md)?.[1] ?? "";
    assert.ok(!backlog.includes("build a spec engine"), "removed from backlog");
  } finally {
    v.cleanup();
  }
});

test("appendBrainIdea adds to ## backlog and is idempotent + round-trips", () => {
  const v = vault(SAMPLE);
  try {
    appendBrainIdea(v.dir, "a brand new idea");
    appendBrainIdea(v.dir, "a brand new idea"); // dup → skipped
    const ideas = readBrainIdeas(v.dir);
    const matches = ideas.filter((i) => i.text === "a brand new idea");
    assert.equal(matches.length, 1, "appended exactly once");
    // The id the hopper would assign matches the re-read id (no echo dup).
    assert.equal(matches[0].id, ideaId("a brand new idea"));
  } finally {
    v.cleanup();
  }
});
