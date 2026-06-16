import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { nightlyCardProjects, queueNextStep, unqueueStep, parseNbId, hasActiveStep, readProjectMode, setProjectMode, NB_PREFIX } from "../src/sources/nightly-cards.js";

function vault(): { root: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "refinery-nb-"));
  const g = join(root, "_inbox", "nightly_builds", "estimator");
  mkdirSync(g, { recursive: true });
  writeFileSync(join(g, "_goal.md"), "---\ntitle: estimator\n---\n# Goal: make the estimator great\nWhy: it matters.\n");
  writeFileSync(join(g, "01-a.md"), "---\ntitle: 01-a\nstep: '1 of 3'\nstatus: done\nrun: runs/x/\n---\nbody a");
  writeFileSync(join(g, "02-b.md"), "---\ntitle: 02-b\nstep: '2 of 3'\nstatus: draft\n---\nbody b");
  writeFileSync(join(g, "03-c.md"), "---\ntitle: 03-c\nstep: '3 of 3'\nstatus: blocked\n---\nbody c");
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

test("nightlyCardProjects groups a goal folder into ONE project with its steps", () => {
  const v = vault();
  try {
    const items = nightlyCardProjects(v.root);
    assert.equal(items.length, 1, "one project per goal folder, not per step");
    const proj = items[0];
    assert.equal(proj.id, `${NB_PREFIX}estimator`);
    assert.equal(parseNbId(proj.id), "estimator");
    const p = proj.payload as { title: string; steps: unknown[]; stepsDone: number; stepsTotal: number; goalBody: string };
    assert.equal(p.title, "make the estimator great", "title from the _goal.md # heading");
    assert.equal(p.stepsTotal, 3);
    assert.equal(p.stepsDone, 1);
    assert.equal(p.steps.length, 3);
    assert.ok(p.goalBody.includes("Why: it matters"));
    // nothing queued → parks (Needs You), not Done
    assert.equal(proj.phaseStatus, "parked");
    assert.equal(proj.phase, "1/3 steps");
  } finally {
    v.cleanup();
  }
});

test("queueNextStep queues the next draft step; unqueueStep reverts it; done stays done", () => {
  const v = vault();
  try {
    const f = queueNextStep(v.root, "estimator");
    assert.equal(f, "02-b.md", "queues the first draft step (not the done or blocked one)");
    let proj = nightlyCardProjects(v.root)[0];
    assert.equal((proj.payload as { queuedCount: number }).queuedCount, 1);
    assert.equal(proj.phaseStatus, "pending", "a queued step → In Progress lane");
    // the 02 card on disk is now queued
    assert.match(readFileSync(join(v.root, "_inbox/nightly_builds/estimator/02-b.md"), "utf8"), /^status: queued$/m);

    unqueueStep(v.root, "estimator");
    proj = nightlyCardProjects(v.root)[0];
    assert.equal((proj.payload as { queuedCount: number }).queuedCount, 0);
    // done step untouched
    assert.match(readFileSync(join(v.root, "_inbox/nightly_builds/estimator/01-a.md"), "utf8"), /^status: done$/m);
  } finally {
    v.cleanup();
  }
});

test("an all-done project lands in the Done lane (not queued tonight)", () => {
  const v = vault();
  try {
    // mark all steps done
    for (const f of ["02-b.md", "03-c.md"]) {
      const p = join(v.root, "_inbox/nightly_builds/estimator", f);
      writeFileSync(p, readFileSync(p, "utf8").replace(/^status:.*$/m, "status: done"));
    }
    const proj = nightlyCardProjects(v.root)[0];
    assert.equal(proj.phaseStatus, "passed");
    assert.equal((proj.payload as { queuedCount: number }).queuedCount, 0);
  } finally {
    v.cleanup();
  }
});

test("no purgatory: queueNextStep force-queues a BLOCKED next step when no draft remains", () => {
  const v = vault();
  try {
    // Mimic the estimator dead-end: done, then the only pending step is blocked.
    const b = join(v.root, "_inbox/nightly_builds/estimator/02-b.md");
    writeFileSync(b, readFileSync(b, "utf8").replace(/^status:.*$/m, "status: done"));
    // next pending is 03-c (blocked); the board must still be able to queue it.
    const f = queueNextStep(v.root, "estimator");
    assert.equal(f, "03-c.md", "a blocked step is force-queueable — never a dead end");
    assert.match(readFileSync(join(v.root, "_inbox/nightly_builds/estimator/03-c.md"), "utf8"), /^status: queued$/m);
    // payload surfaces the override hint when the *next* pending step is blocked
    const b2 = join(v.root, "_inbox/nightly_builds/estimator/02-b.md");
    writeFileSync(b2, readFileSync(b2, "utf8").replace(/^status:.*$/m, "status: draft")); // reset for nextStatus probe
    unqueueStep(v.root, "estimator");
    // now 02 draft is next, 03 blocked — nextStatus should be the draft (02)
    const p = nightlyCardProjects(v.root)[0].payload as { nextStatus: string; nextBlocked: boolean };
    assert.equal(p.nextStatus, "draft");
    assert.equal(p.nextBlocked, false);
  } finally {
    v.cleanup();
  }
});

test("hasActiveStep reflects a queued/running step", () => {
  const v = vault();
  try {
    assert.equal(hasActiveStep(v.root, "estimator"), false);
    queueNextStep(v.root, "estimator");
    assert.equal(hasActiveStep(v.root, "estimator"), true);
  } finally {
    v.cleanup();
  }
});

test("project mode round-trips through _goal.md (default nightly)", () => {
  const v = vault();
  try {
    assert.equal(readProjectMode(v.root, "estimator"), "nightly", "default mode is nightly");
    assert.equal(nightlyCardProjects(v.root)[0].payload && (nightlyCardProjects(v.root)[0].payload as { mode: string }).mode, "nightly");
    assert.equal(setProjectMode(v.root, "estimator", "immediate"), true);
    assert.equal(readProjectMode(v.root, "estimator"), "immediate");
    assert.equal((nightlyCardProjects(v.root)[0].payload as { mode: string }).mode, "immediate");
    // flip back
    setProjectMode(v.root, "estimator", "nightly");
    assert.equal(readProjectMode(v.root, "estimator"), "nightly");
  } finally {
    v.cleanup();
  }
});
