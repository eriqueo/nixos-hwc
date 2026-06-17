// Brain-ideas source — the inbound + outbound bridge between the brain vault's
// _ideas.md backlog/drafted lines and the engine hopper. The vault is the
// source of truth for raw ideas; this module keeps the two in sync BOTH ways:
//
//   brain → hopper (syncBrainIdeas):
//     • a backlog/drafted line with no store item → saved as an UNTRIAGED Item
//       (so it lands in the hopper, marked `source: "brain idea"`).
//     • a brain-idea Item that is STILL untriaged and whose line vanished from
//       the vault → deleted. (A promoted idea has a real genre, so it is never
//       deleted nor re-created — it's a project now.)
//
//   hopper → brain (write-back):
//     • appendBrainIdea  — a NEW idea typed into the hopper box → `## backlog`.
//     • promoteBrainIdea — an idea promoted to a project → its line is cut from
//       backlog/drafted and appended to `## promoted` (annotated with genre).
//     • removeBrainIdea  — an idea deleted on the board → its line is removed.
//
// The keystone is a DETERMINISTIC, content-derived id (`brain-<hash>`): the same
// idea text always yields the same id, so the reconcile is idempotent and the
// round-trip (append → re-read) never echoes into a duplicate.

import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { Item, ItemStore } from "../contracts.js";
import { UNTRIAGED } from "../triage.js";

export const BRAIN_PREFIX = "brain-";
export const BRAIN_SOURCE = "brain idea";
const SECTIONS = new Set(["backlog", "drafted"]);

export interface BrainIdea {
  id: string; // deterministic: brain-<hash of text>
  text: string; // the cleaned idea line (no leading "- ", no html comments)
  section: string; // backlog | drafted
  goalId: string; // "(root)" or a goal folder name
}

/** Normalize a list line OR a raw idea to its comparison key: drop the leading
 *  "- ", strip html comments, trim, lowercase. Matching is case-insensitive so
 *  trivial capitalization drift doesn't orphan an item. */
function norm(s: string): string {
  return s
    .replace(/^\s*-\s+/, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .trim()
    .toLowerCase();
}

/** Stable djb2 hash → base36. Deterministic across runs (no Date.now): an
 *  unchanged idea line keeps its id, which is what makes the sync idempotent. */
function hash(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = (((h << 5) + h) ^ s.charCodeAt(i)) >>> 0;
  return h.toString(36);
}

/** The id an idea text maps to. Hashing the normalized text means an edit to an
 *  idea is treated as a new idea (the old untriaged one is reconciled away). */
export function ideaId(text: string): string {
  return `${BRAIN_PREFIX}${hash(norm(text))}`;
}

export function isBrainIdea(item: Item): boolean {
  return (
    item.payload != null &&
    typeof item.payload === "object" &&
    (item.payload as { source?: unknown }).source === BRAIN_SOURCE
  );
}

// ── vault paths ───────────────────────────────────────────────────────────────

const nbDir = (vaultDir: string): string => join(vaultDir, "_inbox", "nightly_builds");
const rootIdeasPath = (vaultDir: string): string => join(nbDir(vaultDir), "_ideas.md");

/** Every _ideas.md under the gauntlet root (root + per-goal), that exists. */
function ideaFiles(vaultDir: string): string[] {
  const base = nbDir(vaultDir);
  const out: string[] = [];
  const root = rootIdeasPath(vaultDir);
  if (existsSync(root)) out.push(root);
  if (existsSync(base)) {
    for (const g of readdirSync(base)) {
      const d = join(base, g);
      if (statSync(d).isDirectory()) {
        const p = join(d, "_ideas.md");
        if (existsSync(p)) out.push(p);
      }
    }
  }
  return out;
}

// ── inbound: read + reconcile ────────────────────────────────────────────────

/** All hopper-eligible ideas from every _ideas.md `## backlog` / `## drafted`
 *  section (root + per-goal). `## new` is the draft-tonight gauntlet queue and
 *  is intentionally excluded. */
export function readBrainIdeas(vaultDir: string): BrainIdea[] {
  const out: BrainIdea[] = [];
  const scan = (file: string, goalId: string): void => {
    if (!existsSync(file)) return;
    let section = "";
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const h = /^##\s+(.*)$/.exec(line);
      if (h) {
        section = h[1].trim().toLowerCase();
        continue;
      }
      if (SECTIONS.has(section) && /^\s*-\s+/.test(line)) {
        const text = line
          .replace(/^\s*-\s+/, "")
          .replace(/<!--[\s\S]*?-->/g, "")
          .trim();
        if (text) out.push({ id: ideaId(text), text, section, goalId });
      }
    }
  };
  scan(rootIdeasPath(vaultDir), "(root)");
  const base = nbDir(vaultDir);
  if (existsSync(base)) {
    for (const g of readdirSync(base)) {
      const d = join(base, g);
      if (statSync(d).isDirectory()) scan(join(d, "_ideas.md"), g);
    }
  }
  return out;
}

/** A fresh UNTRIAGED Item for a brain idea — the hopper shape (genre untriaged,
 *  parked at the synthetic `triage` phase awaiting human promotion). */
export function makeIdeaItem(idea: BrainIdea, clock: () => string): Item {
  return {
    id: idea.id,
    genre: UNTRIAGED,
    phase: "triage",
    phaseStatus: "parked",
    parkedReason: "from the brain — promote it to start a project",
    payload: {
      input: idea.text,
      title: idea.text.length > 80 ? `${idea.text.slice(0, 77)}…` : idea.text,
      source: BRAIN_SOURCE,
      brainSection: idea.section,
      brainGoal: idea.goalId,
    },
    history: [{ phase: "triage", status: "parked", at: clock(), note: "imported from brain _ideas.md" }],
  };
}

/** Reconcile the store against the vault's ideas. Adds new ones, removes
 *  untriaged ones whose source line is gone. Never touches a promoted idea. */
export async function syncBrainIdeas(
  store: ItemStore,
  vaultDir: string,
  clock: () => string,
): Promise<{ added: number; removed: number }> {
  const ideas = readBrainIdeas(vaultDir);
  const want = new Map(ideas.map((i) => [i.id, i]));
  const existing = await store.list();
  const haveIds = new Set(existing.map((e) => e.id));

  let added = 0;
  for (const idea of ideas) {
    if (!haveIds.has(idea.id)) {
      await store.save(makeIdeaItem(idea, clock));
      added++;
    }
  }
  let removed = 0;
  for (const item of existing) {
    if (isBrainIdea(item) && item.genre === UNTRIAGED && !want.has(item.id)) {
      await store.delete(item.id);
      removed++;
    }
  }
  return { added, removed };
}

// ── outbound: write-back into _ideas.md ──────────────────────────────────────

const isHeader = (l: string): boolean => /^##\s+/.test(l);

/** Insert a list line at the end of `## section` (creating the section at EOF if
 *  absent). Returns the new file text (always newline-terminated). */
function appendToSection(text: string, section: string, listLine: string): string {
  const body = text.replace(/\n+$/, "");
  if (!body.trim()) return `## ${section}\n${listLine}\n`;
  const lines = body.split("\n");
  const sectionRe = new RegExp(`^##\\s+${section}\\b`, "i");
  const headerIdx = lines.findIndex((l) => sectionRe.test(l));
  if (headerIdx === -1) return [...lines, "", `## ${section}`, listLine, ""].join("\n");

  let end = lines.length;
  for (let i = headerIdx + 1; i < lines.length; i++) {
    if (isHeader(lines[i])) {
      end = i;
      break;
    }
  }
  let insertAt = headerIdx + 1;
  for (let i = headerIdx + 1; i < end; i++) if (lines[i].trim() !== "") insertAt = i + 1;
  lines.splice(insertAt, 0, listLine);
  return `${lines.join("\n")}\n`;
}

/** Remove the first backlog/drafted/new list line matching `target` (never the
 *  `## promoted` section). Returns {text, removed}. */
function removeLineByText(text: string, target: string): { text: string; removed: boolean } {
  const lines = text.replace(/\n+$/, "").split("\n");
  const key = norm(target);
  let section = "";
  for (let i = 0; i < lines.length; i++) {
    const h = /^##\s+(.*)$/.exec(lines[i]);
    if (h) {
      section = h[1].trim().toLowerCase();
      continue;
    }
    if (section === "promoted") continue;
    if (/^\s*-\s+/.test(lines[i]) && norm(lines[i]) === key) {
      lines.splice(i, 1);
      return { text: `${lines.join("\n")}\n`, removed: true };
    }
  }
  return { text, removed: false };
}

/** True if any _ideas.md already carries this idea (in any non-promoted section). */
function hasIdea(vaultDir: string, text: string): boolean {
  const key = norm(text);
  for (const f of ideaFiles(vaultDir)) {
    let section = "";
    for (const line of readFileSync(f, "utf8").split("\n")) {
      const h = /^##\s+(.*)$/.exec(line);
      if (h) {
        section = h[1].trim().toLowerCase();
        continue;
      }
      if (section !== "promoted" && /^\s*-\s+/.test(line) && norm(line) === key) return true;
    }
  }
  return false;
}

/** Append a new idea to the root `## backlog` (idempotent — skips if present). */
export function appendBrainIdea(vaultDir: string, text: string): void {
  if (hasIdea(vaultDir, text)) return;
  const root = rootIdeasPath(vaultDir);
  const cur = existsSync(root) ? readFileSync(root, "utf8") : "";
  writeFileSync(root, appendToSection(cur, "backlog", `- ${text}`));
}

/** Remove an idea's line from whichever _ideas.md holds it. */
export function removeBrainIdea(vaultDir: string, text: string): void {
  for (const f of ideaFiles(vaultDir)) {
    const { text: next, removed } = removeLineByText(readFileSync(f, "utf8"), text);
    if (removed) {
      writeFileSync(f, next);
      return;
    }
  }
}

/** Cut a promoted idea from backlog/drafted and record it under the root
 *  `## promoted` section, annotated with the genre it became. */
export function promoteBrainIdea(vaultDir: string, text: string, genre: string, clock: () => string): void {
  removeBrainIdea(vaultDir, text);
  const root = rootIdeasPath(vaultDir);
  const cur = existsSync(root) ? readFileSync(root, "utf8") : "";
  const date = clock().slice(0, 10);
  writeFileSync(root, appendToSection(cur, "promoted", `- ${text}  <!-- → ${genre} ${date} -->`));
}
