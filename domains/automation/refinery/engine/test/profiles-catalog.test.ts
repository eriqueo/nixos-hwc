import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { ProfileCatalog } from "../src/profiles/catalog.js";
import { resolveLlm } from "../src/adapters/resolver.js";

function profileYaml(genre: string, extra = ""): string {
  return `genre: ${genre}\nsource: cli\ngates:\n  - stepwise-refinement\nexecuteMode: none\neffectors:\n  - write-spec\n${extra}`;
}

function makeDir(): { dir: string; state: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "refinery-profiles-"));
  const dir = join(root, "profiles");
  mkdirSync(dir, { recursive: true });
  return {
    dir,
    state: join(root, "state", "enabled.json"),
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

test("catalog lists profiles with resolved defaults (label, enabled, llmProvider)", () => {
  const { dir, state, cleanup } = makeDir();
  try {
    writeFileSync(join(dir, "project-ideation.yaml"), profileYaml("project-ideation"));
    writeFileSync(
      join(dir, "datax-sr.yaml"),
      profileYaml("datax-sr", "label: DataX SR\nllmProvider: ollama\nenabled: false\n"),
    );
    const cat = new ProfileCatalog({ dir, statePath: state });
    const all = cat.list();
    assert.deepEqual(all.map((p) => p.genre), ["datax-sr", "project-ideation"]); // sorted
    const sr = cat.get("datax-sr")!;
    assert.equal(sr.label, "DataX SR");
    assert.equal(sr.llmProvider, "ollama");
    assert.equal(sr.enabled, false); // from file
    const pi = cat.get("project-ideation")!;
    assert.equal(pi.label, "project-ideation"); // defaulted to genre
    assert.equal(pi.llmProvider, "claude-cli"); // defaulted
    assert.equal(pi.enabled, true); // defaulted
  } finally {
    cleanup();
  }
});

test("enabled() returns only enabled profiles; setEnabled overlay wins over file", () => {
  const { dir, state, cleanup } = makeDir();
  try {
    writeFileSync(join(dir, "a.yaml"), profileYaml("a"));
    writeFileSync(join(dir, "b.yaml"), profileYaml("b", "enabled: false\n"));
    const cat = new ProfileCatalog({ dir, statePath: state });
    assert.deepEqual(cat.enabled().map((p) => p.genre), ["a"]);

    // Toggle b on and a off via the overlay (no file rewrite).
    cat.setEnabled("b", true);
    cat.setEnabled("a", false);
    assert.ok(existsSync(state), "overlay state file written");
    assert.deepEqual(cat.enabled().map((p) => p.genre), ["b"]);

    // A fresh catalog over the same dir+state sees the overlay.
    const cat2 = new ProfileCatalog({ dir, statePath: state });
    assert.equal(cat2.get("a")!.enabled, false);
    assert.equal(cat2.get("b")!.enabled, true);
  } finally {
    cleanup();
  }
});

test("setEnabled throws for an unknown genre", () => {
  const { dir, state, cleanup } = makeDir();
  try {
    writeFileSync(join(dir, "a.yaml"), profileYaml("a"));
    const cat = new ProfileCatalog({ dir, statePath: state });
    assert.throws(() => cat.setEnabled("ghost", true), /no profile for genre "ghost"/);
  } finally {
    cleanup();
  }
});

test("resolveLlm maps provider keys to adapters and throws on unknown", () => {
  // We only assert it returns an object with complete() — no network calls.
  assert.equal(typeof resolveLlm("claude-cli").complete, "function");
  assert.equal(typeof resolveLlm("anthropic-api").complete, "function");
  assert.equal(typeof resolveLlm("ollama").complete, "function");
  assert.equal(typeof resolveLlm(undefined).complete, "function"); // defaults to claude-cli
  assert.throws(() => resolveLlm("gpt-5"), /unknown llmProvider "gpt-5"/);
});
