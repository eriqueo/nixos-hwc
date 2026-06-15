import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { nightlyCardProjects, NB_PREFIX } from "../src/sources/nightly-cards.js";

test("nightlyCardProjects mirrors vault cards into read-only nightly-build items in the right lanes", () => {
  const root = mkdtempSync(join(tmpdir(), "refinery-nb-"));
  try {
    const g = join(root, "_inbox", "nightly_builds", "refinery");
    mkdirSync(g, { recursive: true });
    writeFileSync(join(g, "01-done.md"), "---\ntitle: Done card\nstatus: done\nrun: runs/x/\npr: 'branch y'\n---\n");
    writeFileSync(join(g, "02-queued.md"), "---\ntitle: Queued card\nstatus: queued\n---\n");
    writeFileSync(join(g, "03-blocked.md"), "---\ntitle: Blocked card\nstatus: 'blocked: 5'\n---\n");
    const items = nightlyCardProjects(root);
    assert.equal(items.length, 3);
    for (const i of items) {
      assert.ok(i.id.startsWith(NB_PREFIX));
      assert.equal(i.genre, "nightly-build");
      assert.equal(i.nightly, true);
      assert.equal((i.payload as { readonly: boolean }).readonly, true);
    }
    const byTitle = Object.fromEntries(items.map((i) => [(i.payload as { title: string }).title, i]));
    assert.equal(byTitle["Done card"].phaseStatus, "passed");
    assert.equal(byTitle["Queued card"].phaseStatus, "pending");
    assert.equal(byTitle["Blocked card"].phaseStatus, "parked");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
