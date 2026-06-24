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
import {
  readReport,
  nightlyCardProjects,
  isProjectComplete,
  graduateProject,
  type NbStep,
} from "../sources/nightly-cards.js";
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
  /** Done steps skipped because they already carry a review record (idempotent —
   *  this is what lets the pass re-run safely without re-reviewing or re-sweeping
   *  old work, replacing the old date-window band-aid). */
  skipped: number;
  opened: number;
  /** Projects that graduated off the gauntlet this pass (all steps done). */
  graduated: string[];
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

const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/** Retry an async op a few times with exponential backoff. Per-card review hits
 *  transient LLM / gh failures (the 2026-06-24 pass lost 3/10 cards this way);
 *  one retry pass recovers most of them. The op must be idempotent — the review
 *  body is (read-only facts, existingPr-before-createPr, overwriting store.save). */
async function withRetry<T>(fn: () => Promise<T>, attempts = 3): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      if (i < attempts - 1) await sleep(2000 * 3 ** i); // 2s, then 6s
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
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
    skipped: 0,
    opened: 0,
    graduated: [],
    byVerdict: { "merge-ready": 0, "needs-work": 0, reject: 0 },
    errors: [],
    items: [],
  };

  for (const card of cards) {
    try {
      // Idempotent skip: a step already reviewed keeps its record and PR — never
      // re-judged. This (not a date window) is what keeps the pass from
      // re-sweeping older done work every morning.
      if (await ports.store.load(card.id)) {
        summary.skipped += 1;
        continue;
      }

      // Per-card retry with backoff: the LLM review + gh calls fail transiently
      // (the 2026-06-24 pass lost 3/10 this way). Retry the whole side-effecting
      // body — facts are read-only, existingPr makes PR creation idempotent, and
      // store.save overwrites — so a retry never double-acts.
      const { persisted, openedNew } = await withRetry(async () => {
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

        const rec: PrReview = { ...review, prUrl: pr.url, prNumber: pr.number };
        await ports.store.save(rec);
        return { persisted: rec, openedNew: !existing };
      });

      if (openedNew) summary.opened += 1;
      summary.reviewed += 1;
      summary.byVerdict[persisted.verdict] += 1;
      summary.items.push(persisted);
    } catch (e) {
      summary.errors.push({ id: card.id, error: (e as Error).message });
    }
  }

  // Exit ramp: a project whose every step is now done graduates off the
  // gauntlet into _finished/ (the Finished page). Done after reviewing so each
  // step's PR + record already exist; the move never clobbers and is reversible
  // via reopenProject ("send back with amendments").
  for (const proj of nightlyCardProjects(cfg.vaultDir)) {
    const payload = proj.payload as { goal: string; steps: NbStep[] };
    if (!isProjectComplete(payload.steps)) continue;
    // Graduate ONLY when every reviewable step (done + has a run dir → produced a
    // branch) carries a review record. Otherwise a card that errored in review
    // (no record) would vanish into _finished/ and never get retried — exactly
    // what swept the 3 errored cards off the board on 2026-06-24. Steps with no
    // run dir produced no branch and don't block graduation.
    const reviewableIds = payload.steps
      .filter((s) => s.run)
      .map((s) => `${payload.goal}/${s.file.replace(/^\d\d-/, "").replace(/\.md$/, "")}`);
    const records = await Promise.all(reviewableIds.map((id) => ports.store.load(id)));
    if (!records.every((r) => r != null)) continue; // an errored/unreviewed step — keep it on the active board
    if (graduateProject(cfg.vaultDir, payload.goal)) {
      summary.graduated.push(payload.goal);
    }
  }

  return summary;
}
