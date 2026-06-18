// Read-only mirror of the live nightly-builds gauntlet, grouped by PROJECT.
//
// Structure in the vault: _inbox/nightly_builds/<goal>/ is a PROJECT (with a
// _goal.md describing it); each NN-*.md inside is a STEP of that project
// (frontmatter: step "N of M", status, run, pr). So one project card carries
// its ordered steps + a progress (done/total), instead of N confusing
// step-cards. The vault stays the source of truth — run.sh @ 01:30 executes
// `queued` step cards; refinery only reads, and flips a step's status for the
// queue gate (setCardStatus). nb:<goal> ids identify a project.

import { readFileSync, writeFileSync, readdirSync, existsSync, statSync, renameSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { Item } from "../contracts.js";

export const NB_PREFIX = "nb:";
export const NIGHTLY_BUILD_GENRE = "nightly-build";

// The exit ramp. A project is work-in-flight while it lives directly under
// _inbox/nightly_builds/<goal>/. When every step is `done` it GRADUATES off the
// gauntlet into _inbox/nightly_builds/_finished/<goal>/ — physically out of the
// active board (and out of run.sh's `*/NN-*.md` queue glob, since it's now two
// levels deeper). A finished project can be sent back with amendments
// (reopenProject), which returns it to the gauntlet with a fresh queued step.
// The leading underscore keeps _finished from being read as a goal folder.
export const FINISHED_DIR = "_finished";

export interface NbStep {
  n: string; // "01"
  file: string; // "01-slug.md"
  title: string;
  status: string;
  step: string; // "2 of 4"
  run: string;
  pr: string;
}

function frontmatter(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  const m = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!m) return out;
  for (const line of m[1].split("\n")) {
    const mm = /^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/.exec(line);
    if (mm) out[mm[1]] = mm[2].replace(/^["']|["']$/g, "").trim();
  }
  return out;
}
function bodyOf(text: string): string {
  const m = /^---\n[\s\S]*?\n---\n?/.exec(text);
  return m ? text.slice(m[0].length).trim() : text.trim();
}

/** nb:<goal> → the goal folder name (the project). */
export function parseNbId(id: string): string | null {
  return id.startsWith(NB_PREFIX) ? id.slice(NB_PREFIX.length) : null;
}

function readSteps(goalDir: string): NbStep[] {
  const steps: NbStep[] = [];
  for (const f of readdirSync(goalDir)) {
    if (!/^\d\d-/.test(f) || !f.endsWith(".md")) continue;
    const fm = frontmatter(readFileSync(join(goalDir, f), "utf8"));
    steps.push({
      n: f.slice(0, 2),
      file: f,
      title: fm.title || f.replace(/\.md$/, ""),
      status: fm.status || "draft",
      step: fm.step || "",
      run: fm.run || "",
      pr: fm.pr || "",
    });
  }
  steps.sort((a, b) => a.file.localeCompare(b.file));
  return steps;
}

function isDone(s: string): boolean { return s.toLowerCase().startsWith("done"); }
function isQueuedish(s: string): boolean { const x = s.toLowerCase(); return x.startsWith("queued") || x.startsWith("running"); }
/** A step that can be queued for a run: anything not already done and not
 *  already queued/running. This deliberately includes `blocked` steps — the
 *  board surfaces those as a "force-queue (override)" so no project can sit in
 *  purgatory with a real pending step and no button to act on it. */
function isPending(s: string): boolean { return !isDone(s) && !isQueuedish(s); }

/** NIGHTLY (wait for the 01:30 timer) vs IMMEDIATE (a queued step kicks a
 *  targeted run right away). Persisted in the project's _goal.md frontmatter. */
export type NbMode = "nightly" | "immediate";

/** Derive a project's (phase, phaseStatus) from its steps for lane placement. */
function projectState(steps: NbStep[]): { phase: string; phaseStatus: Item["phaseStatus"]; parkedReason?: string } {
  const total = steps.length;
  const done = steps.filter((s) => isDone(s.status)).length;
  const queued = steps.filter((s) => isQueuedish(s.status));
  const phase = `${done}/${total} steps`;
  if (total > 0 && done === total) return { phase, phaseStatus: "passed" };
  if (queued.length) return { phase, phaseStatus: "pending", parkedReason: `${queued.length} queued tonight` };
  return { phase, phaseStatus: "parked", parkedReason: "nothing queued — pick the next step" };
}

/** True once a project has nothing left to do — every step is `done`. This is
 *  the auto-graduation signal: such a project belongs on the Finished page. */
export function isProjectComplete(steps: NbStep[]): boolean {
  return steps.length > 0 && steps.every((s) => isDone(s.status));
}

/** Build one read-only project Item from a goal dir. `finished` flags graduated
 *  projects (Finished page); their id is namespaced so the two sets never
 *  collide and the board can route actions to the right lane. */
function buildProjectItem(dir: string, goalId: string, finished: boolean): Item | null {
  const steps = readSteps(dir);
  if (!steps.length) return null;

  // _goal.md → project title + description + run mode
  let title = goalId;
  let goalBody = "";
  let mode: NbMode = "nightly";
  const goalPath = join(dir, "_goal.md");
  if (existsSync(goalPath)) {
    const gtext = readFileSync(goalPath, "utf8");
    goalBody = bodyOf(gtext);
    const h = /^#\s+(.*)$/m.exec(goalBody);
    if (h) title = h[1].trim().replace(/^Goal:\s*/i, "");
    if (frontmatter(gtext).mode === "immediate") mode = "immediate";
  }
  const nextPending = steps.find((s) => isPending(s.status));

  const { phase, phaseStatus, parkedReason } = projectState(steps);
  const done = steps.filter((s) => isDone(s.status)).length;
  const queuedCount = steps.filter((s) => isQueuedish(s.status)).length;
  return {
    id: `${finished ? FINISHED_PREFIX : NB_PREFIX}${goalId}`,
    genre: NIGHTLY_BUILD_GENRE,
    phase,
    phaseStatus: finished ? "passed" : phaseStatus,
    parkedReason: finished ? undefined : parkedReason,
    payload: {
      title,
      goal: goalId,
      goalBody,
      steps,
      stepsDone: done,
      stepsTotal: steps.length,
      queuedCount,
      mode,
      // The next actionable step (draft or blocked) + whether it's a blocked
      // override, so the board can always render exactly one queue control.
      nextStatus: nextPending ? nextPending.status : "",
      nextBlocked: nextPending ? nextPending.status.toLowerCase().startsWith("blocked") : false,
      finished,
      readonly: true,
      source: finished ? "nightly-builds (finished)" : "nightly-builds project",
    },
    history: [],
    nightly: true,
    nightlyPriority: 0,
  };
}

/** One read-only Item per ACTIVE nightly-builds project (goal folder). Skips
 *  `_`-prefixed dirs (_finished, and any meta) so graduated work never shows on
 *  the gauntlet. */
export function nightlyCardProjects(vaultDir: string): Item[] {
  const base = join(vaultDir, "_inbox", "nightly_builds");
  if (!existsSync(base)) return [];
  const out: Item[] = [];
  for (const goalId of readdirSync(base)) {
    if (goalId.startsWith("_")) continue; // _finished / meta — not a goal
    const dir = join(base, goalId);
    if (!statSync(dir).isDirectory()) continue;
    const item = buildProjectItem(dir, goalId, false);
    if (item) out.push(item);
  }
  out.sort((a, b) => a.id.localeCompare(b.id));
  return out;
}

export const FINISHED_PREFIX = "nbf:";

/** nbf:<goal> → the finished goal folder name. */
export function parseFinishedId(id: string): string | null {
  return id.startsWith(FINISHED_PREFIX) ? id.slice(FINISHED_PREFIX.length) : null;
}

/** One read-only Item per FINISHED project (graduated off the gauntlet). */
export function finishedProjects(vaultDir: string): Item[] {
  const base = join(vaultDir, "_inbox", "nightly_builds", FINISHED_DIR);
  if (!existsSync(base)) return [];
  const out: Item[] = [];
  for (const goalId of readdirSync(base)) {
    if (goalId.startsWith("_")) continue;
    const dir = join(base, goalId);
    if (!statSync(dir).isDirectory()) continue;
    const item = buildProjectItem(dir, goalId, true);
    if (item) out.push(item);
  }
  out.sort((a, b) => a.id.localeCompare(b.id));
  return out;
}

/** Graduate a project off the gauntlet → _finished/. Returns false if the
 *  source is missing or a finished project of that name already exists (never
 *  clobbers). The move is atomic (rename within one filesystem). */
export function graduateProject(vaultDir: string, goalId: string): boolean {
  if (goalId.startsWith("_") || goalId.includes("/")) return false;
  const from = join(vaultDir, "_inbox", "nightly_builds", goalId);
  const to = join(vaultDir, "_inbox", "nightly_builds", FINISHED_DIR, goalId);
  if (!existsSync(from) || existsSync(to)) return false;
  mkdirSync(dirname(to), { recursive: true });
  renameSync(from, to);
  return true;
}

/** Send a finished project back to the gauntlet, optionally with an amendment:
 *  a fresh `NN-amendment-*.md` step (status queued) carrying the note, so the
 *  re-opened project has something actionable to run rather than landing back
 *  as all-done. Returns the new step file (or "" when no amendment) or null on
 *  failure. */
export function reopenProject(
  vaultDir: string,
  goalId: string,
  amendment?: string,
): string | null {
  if (goalId.startsWith("_") || goalId.includes("/")) return null;
  const from = join(vaultDir, "_inbox", "nightly_builds", FINISHED_DIR, goalId);
  const to = join(vaultDir, "_inbox", "nightly_builds", goalId);
  if (!existsSync(from) || existsSync(to)) return null;
  renameSync(from, to);
  if (!amendment || !amendment.trim()) return "";

  const steps = readSteps(to);
  const lastN = steps.reduce((max, s) => Math.max(max, Number(s.n) || 0), 0);
  const nn = String(lastN + 1).padStart(2, "0");
  const file = `${nn}-amendment.md`;
  const title = `${nn} — amendment`;
  writeFileSync(
    join(to, file),
    `---\ntitle: "${title}"\ngoal: "[[_goal]]"\nstep: "${nn}"\nstatus: queued\nrun: ""\npr: ""\n---\n\n# ${title}\n\n${amendment.trim()}\n`,
  );
  return file;
}

/** Flip one step card's status (the queue gate). goalId + step file. */
function setStatus(vaultDir: string, goalId: string, file: string, newStatus: string): boolean {
  const path = join(vaultDir, "_inbox", "nightly_builds", goalId, file);
  if (!existsSync(path)) return false;
  const text = readFileSync(path, "utf8");
  const m = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!m) return false;
  const newFm = /^status:.*$/m.test(m[1])
    ? m[1].replace(/^status:.*$/m, `status: ${newStatus}`)
    : `${m[1]}\nstatus: ${newStatus}`;
  writeFileSync(path, text.replace(m[1], newFm));
  return true;
}

/** Queue the next pending step of a project (draft OR blocked — the latter is a
 *  deliberate override so a blocked step is never a dead end). Returns the file
 *  or null. */
export function queueNextStep(vaultDir: string, goalId: string): string | null {
  const dir = join(vaultDir, "_inbox", "nightly_builds", goalId);
  if (!existsSync(dir)) return null;
  const next = readSteps(dir).find((s) => isPending(s.status));
  if (!next) return null;
  return setStatus(vaultDir, goalId, next.file, "queued") ? next.file : null;
}

/** True if the project already has a queued (or running) step — used to avoid
 *  double-queuing on a "Run now" when something is already in flight. */
export function hasActiveStep(vaultDir: string, goalId: string): boolean {
  const dir = join(vaultDir, "_inbox", "nightly_builds", goalId);
  if (!existsSync(dir)) return false;
  return readSteps(dir).some((s) => isQueuedish(s.status));
}

/** Read a project's run mode from its _goal.md frontmatter (default nightly). */
export function readProjectMode(vaultDir: string, goalId: string): NbMode {
  const goalPath = join(vaultDir, "_inbox", "nightly_builds", goalId, "_goal.md");
  if (!existsSync(goalPath)) return "nightly";
  return frontmatter(readFileSync(goalPath, "utf8")).mode === "immediate" ? "immediate" : "nightly";
}

/** Persist a project's run mode into its _goal.md frontmatter. */
export function setProjectMode(vaultDir: string, goalId: string, mode: NbMode): boolean {
  const goalPath = join(vaultDir, "_inbox", "nightly_builds", goalId, "_goal.md");
  if (!existsSync(goalPath)) return false;
  const text = readFileSync(goalPath, "utf8");
  const m = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!m) return false;
  const newFm = /^mode:.*$/m.test(m[1])
    ? m[1].replace(/^mode:.*$/m, `mode: ${mode}`)
    : `${m[1]}\nmode: ${mode}`;
  writeFileSync(goalPath, text.replace(m[1], newFm));
  return true;
}

/** Unqueue a project's currently-queued step (→ draft). Returns the file or null. */
export function unqueueStep(vaultDir: string, goalId: string): string | null {
  const dir = join(vaultDir, "_inbox", "nightly_builds", goalId);
  if (!existsSync(dir)) return null;
  const q = readSteps(dir).find((s) => s.status.toLowerCase().startsWith("queued"));
  if (!q) return null;
  return setStatus(vaultDir, goalId, q.file, "draft") ? q.file : null;
}

/** Read a REPORT.md from a run dir relative to baseDir (path traversal guarded). */
export function readReport(baseDir: string, run: string): string | null {
  if (!run || run.includes("..") || run.startsWith("/")) return null;
  const path = join(baseDir, run.replace(/\/$/, ""), "REPORT.md");
  return existsSync(path) ? readFileSync(path, "utf8") : null;
}
