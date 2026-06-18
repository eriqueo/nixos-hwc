// Orchestrator for the morning PR-review pass. Pure control flow with every
// side effect behind an injected port (GitFactsPort / GitHubPort / ReviewsStore
// / LlmPort). The vault read reuses the nightly-cards conventions: a step card
// is "done" when its frontmatter status starts with "done" and it carries a
// `run:` dir; the branch is parsed exactly as nightly-builds/run.sh does
// (`branch \`x\`` in the body, else `nightly/<date>-<goal>-<slug>`).
//
// Closes the root gap: run.sh pushes a branch but never opens a PR. Here we
// open the PR (idempotently — existingPr first), judge the branch, and persist
// one PrReview per card. Fail-loud at boundaries, recover-silently per card:
// one card's failure is collected, never aborts the pass.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";
import { LlmPort } from "../gates/llm-port.js";
import { readReport } from "../sources/nightly-cards.js";
import { PrReview } from "./contract.js";
import { GitFactsPort, GitHubPort, ReviewsStore } from "./ports.js";
import { reviewBranch, ReviewInput } from "./reviewer.js";

export interface MorningReviewConfig {
  vaultDir: string;
  defaultRepo: string;
  /** Only review cards whose run dir / report matches this date (YYYY-MM-DD); omit to take all done cards. */
  date?: string;
}

export interface MorningReviewPorts {
  facts: GitFactsPort;
  github: GitHubPort;
  store: ReviewsStore;
  llm: LlmPort;
  clock?: () => string;
}

export interface MorningReviewSummary {
  reviewed: number;
  opened: number;
  byVerdict: { "merge-ready": number; "needs-work": number; reject: number };
  errors: Array<{ id: string; error: string }>;
  items: PrReview[];
}

/** A done card discovered in the vault, with the facts needed to review it. */
interface DoneCard {
  id: string; // "<goal>/<slug>"
  goal: string;
  cardSlug: string;
  title: string;
  repo: string;
  branch: string;
  run: string; // "runs/<RUN_NAME>/"
  body: string;
}

// ── Vault read (mirrors nightly-cards frontmatter/body parsing) ──────────────

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
function isDone(s: string): boolean {
  return s.toLowerCase().startsWith("done");
}

/** Branch exactly as run.sh derives it: card body `branch \`x\``, else nightly/<run-name>. */
function deriveBranch(body: string, goal: string, slug: string, run: string): string {
  const m = /branch `([^`]+)`/.exec(body);
  if (m) return m[1];
  // RUN_NAME is "<date>-<goal>-<slug>"; recover it from the run dir if present.
  const runName = run.replace(/^runs\//, "").replace(/\/$/, "");
  return runName ? `nightly/${runName}` : `nightly/${goal}-${slug}`;
}

/** Scan the vault for last-night done step cards (status done + a run dir). */
export function listDoneCards(cfg: MorningReviewConfig): DoneCard[] {
  const base = join(cfg.vaultDir, "_inbox", "nightly_builds");
  if (!existsSync(base)) return [];
  const out: DoneCard[] = [];
  for (const goal of readdirSync(base)) {
    const dir = join(base, goal);
    if (!statSync(dir).isDirectory()) continue;
    for (const f of readdirSync(dir)) {
      if (!/^\d\d-/.test(f) || !f.endsWith(".md")) continue;
      const text = readFileSync(join(dir, f), "utf8");
      const fm = frontmatter(text);
      if (!isDone(fm.status || "")) continue;
      if (!fm.run) continue; // a done card with no run dir produced no branch to review
      if (cfg.date && !fm.run.includes(cfg.date)) continue;
      const slug = f.replace(/^\d\d-/, "").replace(/\.md$/, "");
      const body = bodyOf(text);
      out.push({
        id: `${goal}/${slug}`,
        goal,
        cardSlug: slug,
        title: fm.title || `${goal}/${slug}`,
        repo: fm.repo || cfg.defaultRepo,
        branch: deriveBranch(body, goal, slug, fm.run),
        run: fm.run,
        body,
      });
    }
  }
  out.sort((a, b) => a.id.localeCompare(b.id));
  return out;
}

/** PR body: what the agent did + the recommendation + a pointer to the REPORT. */
function prBody(review: PrReview): string {
  const lines = [
    "## What was done",
    review.whatWasDone,
    "",
    "## Recommendation",
    review.recommendation,
  ];
  if (review.reportRelPath) {
    lines.push("", `Full report: \`${review.reportRelPath}REPORT.md\``);
  }
  lines.push("", "_Opened by the refinery morning PR-review pass._");
  return lines.join("\n");
}

/**
 * Review every last-night done card: gather git facts, judge the branch, open a
 * PR if none exists, persist the record. Per-card failures are collected so one
 * bad card never aborts the pass.
 */
export async function runMorningReview(
  cfg: MorningReviewConfig,
  ports: MorningReviewPorts,
): Promise<MorningReviewSummary> {
  const now = ports.clock ?? (() => new Date().toISOString());
  const cards = listDoneCards(cfg);

  const summary: MorningReviewSummary = {
    reviewed: 0,
    opened: 0,
    byVerdict: { "merge-ready": 0, "needs-work": 0, reject: 0 },
    errors: [],
    items: [],
  };

  for (const card of cards) {
    try {
      const base = await ports.facts.resolveBase(card.repo);
      const [diffstat, commits, mergeable] = await Promise.all([
        ports.facts.diffstat({ repo: card.repo, base, branch: card.branch }),
        ports.facts.commits({ repo: card.repo, base, branch: card.branch }),
        ports.facts
          .isMergeable({ repo: card.repo, base, branch: card.branch })
          .then((x) => x as boolean | null)
          .catch(() => null),
      ]);

      const reportText = readReport(cfg.vaultDir, card.run);

      const input: ReviewInput = {
        id: card.id,
        goal: card.goal,
        cardSlug: card.cardSlug,
        title: card.title,
        repo: card.repo,
        branch: card.branch,
        base,
        diffstat,
        commits,
        mergeable,
        reportText,
        cardBody: card.body,
        reportRelPath: card.run,
        reviewedAt: now(),
      };

      const review = await reviewBranch(input, ports.llm);

      // Open the PR idempotently: reuse an existing one, else create.
      const existing = await ports.github.existingPr({ repo: card.repo, branch: card.branch });
      const pr =
        existing ??
        (await ports.github.createPr({
          repo: card.repo,
          base,
          branch: card.branch,
          title: card.title,
          body: prBody(review),
        }));
      if (!existing) summary.opened += 1;

      const persisted: PrReview = { ...review, prUrl: pr.url, prNumber: pr.number };
      await ports.store.save(persisted);

      summary.reviewed += 1;
      summary.byVerdict[persisted.verdict] += 1;
      summary.items.push(persisted);
    } catch (e) {
      summary.errors.push({ id: card.id, error: (e as Error).message });
    }
  }

  return summary;
}
