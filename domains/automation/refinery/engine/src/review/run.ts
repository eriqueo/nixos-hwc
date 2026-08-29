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
  setCardPr,
  parseNightlyCardFilename,
  type NbStep,
} from "../sources/nightly-cards.js";
import { PrReview, ReviewCase } from "./contract.js";
import { GitFactsPort, GitHubPort, ReviewsStore } from "./ports.js";
import { reviewBranch, ReviewInput } from "./reviewer.js";

export interface MorningReviewConfig {
  vaultDir: string;
  defaultRepo: string;
  /** Only review cards whose run dir / report matches this date (YYYY-MM-DD); omit to take all done cards. */
  date?: string;
  /** Total external attempts before a case becomes terminal dead. */
  maxAttempts?: number;
}

export interface MorningReviewPorts {
  facts: GitFactsPort;
  github: GitHubPort;
  store: ReviewsStore;
  llm: LlmPort;
  clock?: () => string;
  /** Composition-root retry delay (production adds jitter; tests can run immediately). */
  retryDelay?: (failedAttempt: number) => Promise<void>;
}

export interface MorningReviewSummary {
  reviewed: number;
  /** Done steps skipped because they already carry a review record (idempotent —
   *  this is what lets the pass re-run safely without re-reviewing or re-sweeping
   *  old work, replacing the old date-window band-aid). */
  skipped: number;
  /** Done branches already integrated into base; skipped before any LLM call. */
  alreadyMerged: number;
  dead: number;
  retryable: number;
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
  file: string; // "NN[-_]<slug>.md" — needed to write the `pr:` field back
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
      const cardName = parseNightlyCardFilename(f);
      if (!cardName) continue;
      const text = readFileSync(join(dir, f), "utf8");
      const fm = frontmatter(text);
      if (!isDone(fm.status || "")) continue;
      if (!fm.run) continue; // a done card with no run dir produced no branch to review
      if (cfg.date && !fm.run.includes(cfg.date)) continue;
      const slug = cardName.slug;
      const body = bodyOf(text);
      out.push({
        id: `${goal}/${slug}`,
        goal,
        cardSlug: slug,
        file: f,
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

/** Retry an async op a few times with exponential backoff. Per-card review hits
 *  transient LLM / gh failures (the 2026-06-24 pass lost 3/10 cards this way);
 *  one retry pass recovers most of them. The op must be idempotent — the review
 *  body is (read-only facts, existingPr-before-createPr, overwriting store.save). */
async function withRetry<T>(
  fn: () => Promise<T>,
  attempts: number,
  onFailure: (error: Error, attempt: number) => Promise<void>,
  delay: (failedAttempt: number) => Promise<void>,
): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e) {
      lastErr = e;
      const error = e instanceof Error ? e : new Error(String(e));
      await onFailure(error, i + 1);
      if (i < attempts - 1) await delay(i + 1);
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
  const maxAttempts = cfg.maxAttempts ?? 3;
  const retryDelay = ports.retryDelay ?? (async () => undefined);
  const cards = listDoneCards(cfg);

  const summary: MorningReviewSummary = {
    reviewed: 0,
    skipped: 0,
    alreadyMerged: 0,
    dead: 0,
    retryable: 0,
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
      // re-sweeping older done work every morning. Backfill the card's `pr:`
      // from the stored record (read-old/write-new): cards reviewed before the
      // write-back existed gain the pointer without being re-reviewed.
      const prior = await ports.store.load(card.id);
      if (prior) {
        summary.skipped += 1;
        if (prior.prUrl) setCardPr(cfg.vaultDir, card.goal, card.file, prior.prUrl);
        continue;
      }

      let reviewCase = await ports.store.loadCase(card.id);
      if (reviewCase?.state === "dead") {
        summary.dead += 1;
        continue;
      }
      if (reviewCase?.state === "already-merged") {
        summary.alreadyMerged += 1;
        continue;
      }

      const saveFailure = async (error: Error): Promise<void> => {
        const attempts = reviewCase?.attempts ?? [];
        const nextAttempt = attempts.length + 1;
        const nextAttempts = [
          ...attempts,
          { attempt: nextAttempt, at: now(), code: error.name || "Error", message: error.message },
        ];
        reviewCase = {
          version: 1,
          id: card.id,
          goal: card.goal,
          cardSlug: card.cardSlug,
          cardFile: card.file,
          title: card.title,
          repo: card.repo,
          branch: card.branch,
          state: nextAttempt >= maxAttempts ? "dead" : "retryable",
          maxAttempts,
          attempts: nextAttempts,
        };
        await ports.store.saveCase(reviewCase);
      };

      const remainingAttempts = Math.max(0, maxAttempts - (reviewCase?.attempts.length ?? 0));
      if (remainingAttempts === 0) {
        summary.dead += 1;
        continue;
      }

      // Terminal preflight before any LLM or PR effect. Direct ancestry catches
      // merge commits; GitHub's merged-PR record catches squash/rebase merges.
      // Any refresh/query failure flows to summary.errors rather than guessing
      // from stale refs or an empty diff.
      const { base, merged } = await withRetry(async () => {
        const resolvedBase = await ports.facts.resolveBase(card.repo);
        const mergedByAncestry = await ports.facts.isMerged({
          repo: card.repo,
          base: resolvedBase,
          branch: card.branch,
        });
        const mergedByGitHub = mergedByAncestry
          ? false
          : await ports.github.isMerged({ repo: card.repo, branch: card.branch });
        return { base: resolvedBase, merged: mergedByAncestry || mergedByGitHub };
      }, remainingAttempts, saveFailure, retryDelay);
      if (merged) {
        const mergedCase: ReviewCase = {
          version: 1,
          id: card.id,
          goal: card.goal,
          cardSlug: card.cardSlug,
          cardFile: card.file,
          title: card.title,
          repo: card.repo,
          branch: card.branch,
          state: "already-merged",
          maxAttempts,
          attempts: reviewCase?.attempts ?? [],
        };
        await ports.store.saveCase(mergedCase);
        summary.alreadyMerged += 1;
        continue;
      }

      // Per-card retry with backoff: the LLM review + gh calls fail transiently
      // (the 2026-06-24 pass lost 3/10 this way). Retry the whole side-effecting
      // body — facts are read-only, existingPr makes PR creation idempotent, and
      // store.save overwrites — so a retry never double-acts.
      const attemptsAfterPreflight = reviewCase?.attempts.length ?? 0;
      const bodyAttempts = Math.max(1, maxAttempts - attemptsAfterPreflight);
      const { persisted, openedNew } = await withRetry(async () => {
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

        const rec: PrReview = { ...review, cardFile: card.file, prUrl: pr.url, prNumber: pr.number };
        await ports.store.save(rec);
        return { persisted: rec, openedNew: !existing };
      }, bodyAttempts, saveFailure, retryDelay);

      await ports.store.deleteCase(card.id);

      if (openedNew) summary.opened += 1;
      summary.reviewed += 1;
      summary.byVerdict[persisted.verdict] += 1;
      summary.items.push(persisted);

      // The stated-but-unimplemented two-way pointer, now real: the PR url is
      // written into the card's `pr:` frontmatter (data, not prose), and the
      // project mirror derives typed `{kind:"pr"}` evidence from that field —
      // so the vault card and the board Item both point at the PR. Idempotent
      // (setCardPr no-ops on an unchanged value); a failed write is recorded,
      // not swallowed — the review record exists but the card pointer doesn't.
      if (persisted.prUrl && !setCardPr(cfg.vaultDir, card.goal, card.file, persisted.prUrl)) {
        summary.errors.push({ id: card.id, error: "review persisted but card `pr:` write-back failed" });
      }
    } catch (e) {
      const c = await ports.store.loadCase(card.id).catch(() => null);
      if (c?.state === "dead") summary.dead += 1;
      else if (c?.state === "retryable") summary.retryable += 1;
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
      .map((s) => `${payload.goal}/${parseNightlyCardFilename(s.file)?.slug ?? s.file}`);
    const terminals = await Promise.all(reviewableIds.map(async (id) => {
      const [review, c] = await Promise.all([ports.store.load(id), ports.store.loadCase(id)]);
      return review != null || c?.state === "dead" || c?.state === "already-merged";
    }));
    if (!terminals.every(Boolean)) continue; // retryable/unreviewed step — keep it active
    if (graduateProject(cfg.vaultDir, payload.goal)) {
      summary.graduated.push(payload.goal);
    }
  }

  return summary;
}
