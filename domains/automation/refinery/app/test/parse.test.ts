// Tests for the read-only hopper parser. A fake vault is built in a tmp dir so
// the pure fs-walking logic (frontmatter, status grouping, card/idea filters)
// is exercised without touching the real brain vault. Run: node --test (Node's
// native type-stripping handles the .ts specifiers, matching the app's build).

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { readCards, readIdeas } from "../src/parse.ts";

function makeVault(): {
  root: string;
  card: (goal: string, file: string, body: string) => void;
  ideas: (goal: string | null, body: string) => void;
  cleanup: () => void;
} {
  const root = mkdtempSync(join(tmpdir(), "refinery-vault-"));
  const base = join(root, "_inbox", "nightly_builds");
  mkdirSync(base, { recursive: true });
  return {
    root,
    card(goal, file, body) {
      const dir = join(base, goal);
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, file), body);
    },
    ideas(goal, body) {
      const dir = goal ? join(base, goal) : base;
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, "_ideas.md"), body);
    },
    cleanup() {
      rmSync(root, { recursive: true, force: true });
    },
  };
}

const fm = (status: string, extra = "") =>
  `---\ntitle: Sample Card\nstatus: ${status}\n${extra}---\nbody text\n`;

test("readCards: normalizes status values into lanes and extracts gate suffix", () => {
  const v = makeVault();
  try {
    v.card("goal-a", "01-first.md", fm("queued"));
    v.card("goal-a", "02-blocked.md", fm('"blocked: human-review"'));
    v.card("goal-a", "03-failed.md", fm("failed: build-gate"));
    v.card("goal-a", "04-done.md", fm("done"));
    v.card("goal-a", "05-running.md", fm("running"));
    v.card("goal-a", "06-bare.md", fm("draft"));
    const cards = readCards(v.root);
    const byFile = Object.fromEntries(cards.map((c) => [c.file, c]));
    assert.equal(byFile["01-first.md"].group, "queued");
    assert.equal(byFile["02-blocked.md"].group, "blocked");
    assert.equal(byFile["02-blocked.md"].gate, "human-review");
    assert.equal(byFile["03-failed.md"].group, "failed");
    assert.equal(byFile["03-failed.md"].gate, "build-gate");
    assert.equal(byFile["04-done.md"].group, "done");
    assert.equal(byFile["05-running.md"].group, "running");
    assert.equal(byFile["06-bare.md"].group, "draft");
    assert.equal(byFile["01-first.md"].gate, null);
  } finally {
    v.cleanup();
  }
});

test("readCards: skips underscore files and non-NN-prefixed markdown", () => {
  const v = makeVault();
  try {
    v.card("goal-a", "01-keep.md", fm("queued"));
    v.card("goal-a", "_goal.md", fm("queued"));
    v.card("goal-a", "_template.md", fm("queued"));
    v.card("goal-a", "notes.md", fm("queued")); // no NN- prefix
    v.card("goal-a", "readme.txt", "not markdown");
    const cards = readCards(v.root);
    assert.deepEqual(cards.map((c) => c.file), ["01-keep.md"]);
  } finally {
    v.cleanup();
  }
});

test("readCards: pulls step/run/pr fields and falls back to filename for title", () => {
  const v = makeVault();
  try {
    v.card(
      "goal-a",
      "01-full.md",
      fm("running", "step: 3/7\nrun: run-2026\npr: '#42'\n"),
    );
    v.card("goal-a", "02-untitled.md", "---\nstatus: draft\n---\nno title\n");
    const cards = readCards(v.root);
    const full = cards.find((c) => c.file === "01-full.md")!;
    assert.equal(full.title, "Sample Card");
    assert.equal(full.step, "3/7");
    assert.equal(full.run, "run-2026");
    assert.equal(full.pr, "#42");
    const untitled = cards.find((c) => c.file === "02-untitled.md")!;
    assert.equal(untitled.title, "02-untitled"); // filename minus .md
  } finally {
    v.cleanup();
  }
});

test("readCards: sorts by goalId+file and spans multiple goal folders", () => {
  const v = makeVault();
  try {
    v.card("goal-b", "01-b.md", fm("queued"));
    v.card("goal-a", "02-a2.md", fm("queued"));
    v.card("goal-a", "01-a1.md", fm("queued"));
    const cards = readCards(v.root);
    assert.deepEqual(
      cards.map((c) => `${c.goalId}/${c.file}`),
      ["goal-a/01-a1.md", "goal-a/02-a2.md", "goal-b/01-b.md"],
    );
  } finally {
    v.cleanup();
  }
});

test("readCards: returns [] when nightly_builds dir is absent", () => {
  const root = mkdtempSync(join(tmpdir(), "refinery-empty-"));
  try {
    assert.deepEqual(readCards(root), []);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("readIdeas: reads new/backlog sections from root and goal _ideas.md, stripping comments", () => {
  const v = makeVault();
  try {
    v.ideas(
      null,
      "## new\n- root idea one <!-- draft-tonight -->\n- root idea two\n## backlog\n- parked idea\n## other\n- ignored\n",
    );
    v.ideas("goal-a", "## new\n- goal idea\n");
    const ideas = readIdeas(v.root);
    const texts = ideas.map((i) => `${i.goalId}:${i.section}:${i.text}`);
    assert.ok(texts.includes("(root):new:root idea one"));
    assert.ok(texts.includes("(root):new:root idea two"));
    assert.ok(texts.includes("(root):backlog:parked idea"));
    assert.ok(texts.includes("goal-a:new:goal idea"));
    // The "## other" bullet must not leak in.
    assert.ok(!texts.some((t) => t.endsWith("ignored")));
  } finally {
    v.cleanup();
  }
});
