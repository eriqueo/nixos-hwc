// Read-only mirror of the live nightly-builds gauntlet cards as refinery
// projects, so they show on the board. The cards in the brain vault
// (_inbox/nightly_builds/*/NN-*.md) remain the source of truth — run.sh flips
// their status nightly; refinery never writes them. Mirror items carry an "nb:"
// id prefix and a readonly payload flag so the detail page hides edit actions.
//
// This is SourcePort Path A (display-only). Driving the overnight timer from
// refinery (writing card status) is a separate, human-gated step.

import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { Item } from "../contracts.js";

export const NB_PREFIX = "nb:";
export const NIGHTLY_BUILD_GENRE = "nightly-build";

/** Parse an "nb:goal/NN-slug" mirror id back into vault coordinates. */
export function parseNbId(id: string): { goalId: string; file: string } | null {
  if (!id.startsWith(NB_PREFIX)) return null;
  const rest = id.slice(NB_PREFIX.length);
  const slash = rest.indexOf("/");
  if (slash < 0) return null;
  return { goalId: rest.slice(0, slash), file: `${rest.slice(slash + 1)}.md` };
}

/**
 * Flip a card's `status:` frontmatter field in place (the Phase-4 queue gate, as
 * a GUI action) — preserving the rest of the frontmatter and the body. This is
 * exactly the hand-edit a human does today; run.sh @ 01:30 still does the work.
 */
export function setCardStatus(vaultDir: string, id: string, newStatus: string): boolean {
  const coords = parseNbId(id);
  if (!coords) return false;
  const path = join(vaultDir, "_inbox", "nightly_builds", coords.goalId, coords.file);
  if (!existsSync(path)) return false;
  const text = readFileSync(path, "utf8");
  const m = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!m) return false;
  const fm = m[1];
  const newFm = /^status:.*$/m.test(fm)
    ? fm.replace(/^status:.*$/m, `status: ${newStatus}`)
    : `${fm}\nstatus: ${newStatus}`;
  writeFileSync(path, text.replace(m[1], newFm));
  return true;
}

/** Read a REPORT.md from a run dir relative to baseDir (path traversal guarded). */
export function readReport(baseDir: string, run: string): string | null {
  if (!run || run.includes("..") || run.startsWith("/")) return null;
  const path = join(baseDir, run.replace(/\/$/, ""), "REPORT.md");
  return existsSync(path) ? readFileSync(path, "utf8") : null;
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

/** Map a card `status:` to the engine's (phase, phaseStatus) for lane placement. */
function mapStatus(status: string): { phase: string; phaseStatus: Item["phaseStatus"] } {
  const s = status.toLowerCase();
  if (s.startsWith("queued")) return { phase: "queued", phaseStatus: "pending" };
  if (s.startsWith("running")) return { phase: "running", phaseStatus: "pending" };
  if (s.startsWith("done")) return { phase: "done", phaseStatus: "passed" };
  if (s.startsWith("failed")) return { phase: status, phaseStatus: "failed" };
  if (s.startsWith("blocked")) return { phase: status, phaseStatus: "parked" };
  // draft / anything else → awaiting a human (Needs You lane)
  return { phase: status || "draft", phaseStatus: "parked" };
}

/** Read the live nightly-builds vault cards as read-only mirror Items. */
export function nightlyCardProjects(vaultDir: string): Item[] {
  const base = join(vaultDir, "_inbox", "nightly_builds");
  if (!existsSync(base)) return [];
  const out: Item[] = [];
  for (const goalId of readdirSync(base)) {
    const dir = join(base, goalId);
    if (!statSync(dir).isDirectory()) continue;
    for (const f of readdirSync(dir)) {
      if (!/^\d\d-/.test(f) || !f.endsWith(".md")) continue;
      const text = readFileSync(join(dir, f), "utf8");
      const fm = frontmatter(text);
      // The card's markdown body (everything after the frontmatter) — this is
      // what makes the card self-explanatory rather than just a slug.
      const fmEnd = /^---\n[\s\S]*?\n---\n?/.exec(text);
      const body = fmEnd ? text.slice(fmEnd[0].length).trim() : text.trim();
      const status = fm.status || "draft";
      const { phase, phaseStatus } = mapStatus(status);
      out.push({
        id: `${NB_PREFIX}${goalId}/${f.replace(/\.md$/, "")}`,
        genre: NIGHTLY_BUILD_GENRE,
        phase,
        phaseStatus,
        parkedReason: phaseStatus === "parked" ? `status: ${status}` : undefined,
        payload: {
          title: fm.title || f.replace(/\.md$/, ""),
          goal: goalId,
          card: f,
          status,
          step: fm.step || "",
          run: fm.run || "",
          pr: fm.pr || "",
          body,
          readonly: true,
          source: "nightly-builds vault card",
        },
        history: [],
        nightly: true,
        nightlyPriority: 0,
      });
    }
  }
  out.sort((a, b) => a.id.localeCompare(b.id));
  return out;
}
