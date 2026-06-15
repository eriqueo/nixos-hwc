// domains/automation/refinery/app/src/parse.ts
//
// Read-only parser over the gauntlet hopper in the brain vault. Knows the card
// frontmatter contract (status vocab) and the _ideas.md section format. Pure
// functions over a vault directory — no network, no writes.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";

export type StatusGroup =
  | "draft"
  | "blocked"
  | "queued"
  | "running"
  | "done"
  | "failed";

export interface Card {
  goalId: string;          // the goal folder name
  file: string;            // NN-slug.md
  title: string;
  status: string;          // raw status value
  group: StatusGroup;      // normalized lane
  gate: string | null;     // suffix after "blocked:"/"failed:" if any
  step: string;
  run: string;
  pr: string;
}

export interface Idea {
  section: "new" | "backlog";
  goalId: string;          // which goal's _ideas.md (usually the gauntlet root)
  text: string;
}

/** Minimal YAML-frontmatter reader for the flat `key: value` fields we need. */
function parseFrontmatter(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  const m = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!m) return out;
  for (const line of m[1].split("\n")) {
    const mm = /^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/.exec(line);
    if (mm) out[mm[1]] = mm[2].replace(/^["']|["']$/g, "").trim();
  }
  return out;
}

function groupOf(status: string): { group: StatusGroup; gate: string | null } {
  const s = status.toLowerCase();
  const suffix = (raw: string) => {
    const i = raw.indexOf(":");
    return i >= 0 ? raw.slice(i + 1).trim() || null : null;
  };
  if (s.startsWith("blocked")) return { group: "blocked", gate: suffix(status) };
  if (s.startsWith("failed")) return { group: "failed", gate: suffix(status) };
  if (s.startsWith("done")) return { group: "done", gate: null };
  if (s.startsWith("running")) return { group: "running", gate: null };
  if (s.startsWith("queued")) return { group: "queued", gate: null };
  return { group: "draft", gate: null };
}

/** All gauntlet cards across every goal folder under _inbox/nightly_builds/. */
export function readCards(vaultDir: string): Card[] {
  const base = join(vaultDir, "_inbox", "nightly_builds");
  const cards: Card[] = [];
  if (!existsSync(base)) return cards;
  for (const goalId of readdirSync(base)) {
    const goalDir = join(base, goalId);
    if (!statSync(goalDir).isDirectory()) continue;
    for (const f of readdirSync(goalDir)) {
      if (!f.endsWith(".md") || f.startsWith("_")) continue; // _goal/_ideas/_template
      if (!/^\d\d-/.test(f)) continue;                       // only NN- cards
      const fm = parseFrontmatter(readFileSync(join(goalDir, f), "utf8"));
      const status = fm.status || "draft";
      const { group, gate } = groupOf(status);
      cards.push({
        goalId,
        file: f,
        title: fm.title || f.replace(/\.md$/, ""),
        status,
        group,
        gate,
        step: fm.step || "",
        run: fm.run || "",
        pr: fm.pr || "",
      });
    }
  }
  cards.sort((a, b) => (a.goalId + a.file).localeCompare(b.goalId + b.file));
  return cards;
}

/** Raw ideas from any _ideas.md `## new` / `## backlog` section in the hopper. */
export function readIdeas(vaultDir: string): Idea[] {
  const base = join(vaultDir, "_inbox", "nightly_builds");
  const ideas: Idea[] = [];
  if (!existsSync(base)) return ideas;

  const scan = (file: string, goalId: string) => {
    if (!existsSync(file)) return;
    let section = "";
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const h = /^##\s+(.*)$/.exec(line);
      if (h) {
        section = h[1].trim().toLowerCase();
        continue;
      }
      if ((section === "new" || section === "backlog") && /^\s*-\s+/.test(line)) {
        const text = line
          .replace(/^\s*-\s+/, "")
          .replace(/<!--[\s\S]*?-->/g, "")
          .trim();
        if (text) ideas.push({ section: section as "new" | "backlog", goalId, text });
      }
    }
  };

  scan(join(base, "_ideas.md"), "(root)");
  for (const goalId of readdirSync(base)) {
    const goalDir = join(base, goalId);
    if (statSync(goalDir).isDirectory()) scan(join(goalDir, "_ideas.md"), goalId);
  }
  return ideas;
}
