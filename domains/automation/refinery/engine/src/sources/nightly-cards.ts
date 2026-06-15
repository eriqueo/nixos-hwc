// Read-only mirror of the live nightly-builds gauntlet cards as refinery
// projects, so they show on the board. The cards in the brain vault
// (_inbox/nightly_builds/*/NN-*.md) remain the source of truth — run.sh flips
// their status nightly; refinery never writes them. Mirror items carry an "nb:"
// id prefix and a readonly payload flag so the detail page hides edit actions.
//
// This is SourcePort Path A (display-only). Driving the overnight timer from
// refinery (writing card status) is a separate, human-gated step.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { Item } from "../contracts.js";

export const NB_PREFIX = "nb:";
export const NIGHTLY_BUILD_GENRE = "nightly-build";

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
      const fm = frontmatter(readFileSync(join(dir, f), "utf8"));
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
