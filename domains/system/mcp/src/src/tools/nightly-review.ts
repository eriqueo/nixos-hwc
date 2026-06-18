/**
 * hwc_nightly_review — review board + merge controls for the nightly-builds
 * PR-review gauntlet.
 *
 * The backend (nightly review pass) writes ONE JSON file per reviewed card to
 * REFINERY_REVIEWS_DIR (default /var/lib/refinery/reviews) — `<safeId>.json`.
 * This tool is the human surface over those records: a kanban board grouped by
 * verdict/status lane, a per-card detail view, and three write actions —
 *   - merge   : `gh pr merge` the card's PR, then flip the review status
 *   - requeue : flip the source nightly_builds card back to `queued` (the queue
 *               gate), best-effort `gh pr close`, mark the review re-queued
 *   - rebuild : drop a spool file a privileged unit consumes (this tool never
 *               runs nixos-rebuild)
 *
 * Boundary data (the review JSON) is parsed by hand — the mcp src carries no
 * zod dependency (see package.json) and node_modules cannot be widened here, so
 * we follow the codebase dialect: a hand-rolled validator that returns null on
 * any malformed record (skipped, not thrown — the board reports the skip count).
 */

import { execFile } from "node:child_process";
import { readFile, writeFile, readdir, mkdir } from "node:fs/promises";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError, catchError } from "../errors.js";

/* ════════════════════════════════════════════════════════════════ */
/*  Late-bound paths                                                */
/* ════════════════════════════════════════════════════════════════ */

const REVIEWS_DIR = process.env.REFINERY_REVIEWS_DIR || "/var/lib/refinery/reviews";
const REBUILD_DIR = "/var/lib/refinery/rebuild-request";
const VAULT_DIR = process.env.REFINERY_VAULT_DIR || "/home/eric/900_vaults/brain";

/* ════════════════════════════════════════════════════════════════ */
/*  Contract — the review record the backend writes                 */
/* ════════════════════════════════════════════════════════════════ */

type Verdict = "merge-ready" | "needs-work" | "reject";
type ReviewStatus = "needs-you" | "merged" | "requeued" | "rejected";

interface Diffstat {
  files: number;
  insertions: number;
  deletions: number;
}

interface Review {
  id: string;
  goal: string;
  cardSlug: string;
  title: string;
  repo: string;
  branch: string;
  base: string;
  prUrl: string | null;
  prNumber: number | null;
  reviewedAt: string;
  verdict: Verdict;
  mergeable: boolean | null;
  diffstat: Diffstat;
  commits: string[];
  whatWasDone: string;
  whatItMeans: string;
  recommendation: string;
  risks: string[];
  status: ReviewStatus;
  reportRelPath: string | null;
}

const VERDICTS: Verdict[] = ["merge-ready", "needs-work", "reject"];
const STATUSES: ReviewStatus[] = ["needs-you", "merged", "requeued", "rejected"];

/** Type guards for the boundary — every field validated before core touches it. */
function isStr(v: unknown): v is string {
  return typeof v === "string";
}
function isStrArr(v: unknown): v is string[] {
  return Array.isArray(v) && v.every((x) => typeof x === "string");
}
function isDiffstat(v: unknown): v is Diffstat {
  if (!v || typeof v !== "object") return false;
  const d = v as Record<string, unknown>;
  return typeof d.files === "number" && typeof d.insertions === "number" && typeof d.deletions === "number";
}

/**
 * Parse + validate one review record. Returns null on ANY structural problem
 * (the board skips it and reports the count) — never throws.
 */
function parseReview(raw: unknown): Review | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;

  if (!isStr(r.id) || !isStr(r.goal) || !isStr(r.cardSlug) || !isStr(r.title)) return null;
  if (!isStr(r.repo) || !isStr(r.branch) || !isStr(r.base) || !isStr(r.reviewedAt)) return null;
  if (!isStr(r.whatWasDone) || !isStr(r.whatItMeans) || !isStr(r.recommendation)) return null;
  if (!VERDICTS.includes(r.verdict as Verdict)) return null;
  if (!STATUSES.includes(r.status as ReviewStatus)) return null;
  if (!isDiffstat(r.diffstat)) return null;
  if (!isStrArr(r.commits) || !isStrArr(r.risks)) return null;

  const prUrl = r.prUrl == null ? null : isStr(r.prUrl) ? r.prUrl : null;
  const prNumber = r.prNumber == null ? null : typeof r.prNumber === "number" ? r.prNumber : null;
  const mergeable = r.mergeable == null ? null : typeof r.mergeable === "boolean" ? r.mergeable : null;
  const reportRelPath = r.reportRelPath == null ? null : isStr(r.reportRelPath) ? r.reportRelPath : null;

  return {
    id: r.id,
    goal: r.goal,
    cardSlug: r.cardSlug,
    title: r.title,
    repo: r.repo,
    branch: r.branch,
    base: r.base,
    prUrl,
    prNumber,
    reviewedAt: r.reviewedAt,
    verdict: r.verdict as Verdict,
    mergeable,
    diffstat: r.diffstat as Diffstat,
    commits: r.commits as string[],
    whatWasDone: r.whatWasDone,
    whatItMeans: r.whatItMeans,
    recommendation: r.recommendation,
    risks: r.risks as string[],
    status: r.status as ReviewStatus,
    reportRelPath,
  };
}

/* ════════════════════════════════════════════════════════════════ */
/*  Filesystem helpers                                              */
/* ════════════════════════════════════════════════════════════════ */

/** Same id→filename mapping the backend uses: non-safe chars → "_". */
function safeId(id: string): string {
  return id.replace(/[^a-zA-Z0-9._-]/g, "_");
}

function reviewPath(id: string): string {
  return join(REVIEWS_DIR, `${safeId(id)}.json`);
}

/** Read + parse all reviews. Returns the valid ones plus the malformed count. */
async function loadAllReviews(): Promise<{ reviews: Review[]; malformed: number }> {
  let files: string[];
  try {
    files = (await readdir(REVIEWS_DIR)).filter((f) => f.endsWith(".json"));
  } catch {
    return { reviews: [], malformed: 0 };
  }
  const reviews: Review[] = [];
  let malformed = 0;
  for (const f of files) {
    try {
      const parsed = parseReview(JSON.parse(await readFile(join(REVIEWS_DIR, f), "utf-8")));
      if (parsed) reviews.push(parsed);
      else malformed++;
    } catch {
      malformed++;
    }
  }
  return { reviews, malformed };
}

/** Load a single review by id (the safeId-mapped file). null if absent/malformed. */
async function loadReview(id: string): Promise<Review | null> {
  try {
    return parseReview(JSON.parse(await readFile(reviewPath(id), "utf-8")));
  } catch {
    return null;
  }
}

/** Persist a review back to its file (status flips). */
async function saveReview(review: Review): Promise<void> {
  await writeFile(reviewPath(review.id), JSON.stringify(review, null, 2) + "\n", "utf-8");
}

/* ════════════════════════════════════════════════════════════════ */
/*  gh shell-out                                                    */
/* ════════════════════════════════════════════════════════════════ */

/**
 * Derive the `-R owner/name` arg gh wants from the stored `repo`. The card's
 * repo may be a full URL, an `owner/name` slug, or a local path; we normalise
 * to `owner/name`. Returns null when we cannot (caller falls back to no -R, but
 * for merge/close we require a slug so gh targets the right remote).
 */
function repoSlug(repo: string): string | null {
  const trimmed = repo.trim().replace(/\.git$/, "").replace(/\/+$/, "");
  // git@github.com:owner/name
  const ssh = /^git@[^:]+:(.+)$/.exec(trimmed);
  if (ssh) return ssh[1];
  // https://github.com/owner/name  (or any host)
  const url = /^https?:\/\/[^/]+\/(.+)$/.exec(trimmed);
  if (url) return url[1];
  // already owner/name (exactly two non-empty path segments)
  const segs = trimmed.split("/").filter(Boolean);
  if (segs.length === 2) return segs.join("/");
  // local path like /home/eric/600_apps/foo → take the last segment as name,
  // but without an owner gh -R is ambiguous; signal "no slug".
  return null;
}

function gh(args: string[]): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    execFile("gh", args, { timeout: 60000, maxBuffer: 4 * 1024 * 1024 }, (error, stdout, stderr) => {
      const code = error && "code" in error ? (error.code as number) : 0;
      resolve({
        exitCode: typeof code === "number" ? code : 1,
        stdout: stdout?.toString() ?? "",
        stderr: stderr?.toString() ?? "",
      });
    });
  });
}

/* ════════════════════════════════════════════════════════════════ */
/*  Card-status flip (the queue gate) — mirrors refinery setStatus  */
/* ════════════════════════════════════════════════════════════════ */

/**
 * Flip the source card's frontmatter `status:` line back to `queued`. The card
 * lives at <vault>/_inbox/nightly_builds/<goal>/<cardSlug>.md. Mirrors the
 * refinery's setStatus (read → frontmatter regex replace → write). Returns
 * false when the file or its frontmatter block is absent.
 */
async function setCardQueued(goal: string, cardSlug: string): Promise<boolean> {
  const path = join(VAULT_DIR, "_inbox", "nightly_builds", goal, `${cardSlug}.md`);
  let text: string;
  try {
    text = await readFile(path, "utf-8");
  } catch {
    return false;
  }
  const m = /^---\n([\s\S]*?)\n---/.exec(text);
  if (!m) return false;
  const newFm = /^status:.*$/m.test(m[1])
    ? m[1].replace(/^status:.*$/m, "status: queued")
    : `${m[1]}\nstatus: queued`;
  await writeFile(path, text.replace(m[1], newFm), "utf-8");
  return true;
}

/* ════════════════════════════════════════════════════════════════ */
/*  Lane derivation + card shaping                                  */
/* ════════════════════════════════════════════════════════════════ */

/** Stable lane order — always present even when empty. */
const LANES = [
  { id: "merge-ready", title: "Merge-ready" },
  { id: "needs-work", title: "Needs work" },
  { id: "reject-rec", title: "Reject (rec.)" },
  { id: "requeued", title: "Re-queued" },
  { id: "merged", title: "Merged" },
  { id: "rejected", title: "Rejected" },
] as const;

/** Map a review to its lane id. Terminal status wins over verdict. */
function laneOf(review: Review): string {
  if (review.status === "merged") return "merged";
  if (review.status === "requeued") return "requeued";
  if (review.status === "rejected") return "rejected";
  switch (review.verdict) {
    case "merge-ready":
      return "merge-ready";
    case "needs-work":
      return "needs-work";
    case "reject":
      return "reject-rec";
  }
}

function priorityOf(verdict: Verdict): "critical" | "normal" | "low" {
  if (verdict === "reject") return "critical";
  if (verdict === "needs-work") return "normal";
  return "low";
}

function toCard(review: Review) {
  return {
    id: review.id,
    kind: "pr",
    label: review.title,
    priority: priorityOf(review.verdict),
    sender: review.goal,
    summary: `${review.whatItMeans} — ${review.recommendation}`,
    branch: review.branch,
    prUrl: review.prUrl,
    prNumber: review.prNumber,
    diffstat: review.diffstat,
    mergeable: review.mergeable,
  };
}

/* ════════════════════════════════════════════════════════════════ */
/*  Tool                                                            */
/* ════════════════════════════════════════════════════════════════ */

export function nightlyReviewTools(): ToolDef[] {
  return [
    {
      name: "hwc_nightly_review",
      description:
        "Nightly-builds PR-review board + merge controls. The review pass writes one JSON record per " +
        "reviewed card to /var/lib/refinery/reviews; this tool surfaces them. " +
        "action=board (default) returns a kanban grouped into stable lanes " +
        "(Merge-ready, Needs work, Reject (rec.), Re-queued, Merged, Rejected). " +
        "action=detail returns one review's full record. " +
        "action=merge runs `gh pr merge` for the card's PR (method=squash|merge|rebuild) and marks it merged. " +
        "action=requeue flips the source card back to queued (re-runs it tonight), closes the PR best-effort, marks it re-queued. " +
        "action=rebuild drops a spool file a privileged unit consumes to rebuild a host (this tool never runs nixos-rebuild).",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["board", "detail", "merge", "requeue", "rebuild"],
            default: "board",
            description: "board = kanban; detail = one record; merge/requeue = write actions on a card; rebuild = request a host rebuild via spool",
          },
          id: {
            type: "string",
            description: "[detail/merge/requeue] Review id (the card's id, as written in the review JSON)",
          },
          method: {
            type: "string",
            enum: ["squash", "merge", "rebuild"],
            default: "squash",
            description: "[merge] gh pr merge strategy (default squash)",
          },
          host: {
            type: "string",
            description: "[rebuild] Target host (default hwc-server)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        const action = (args.action as string) || "board";

        /* ── board ──────────────────────────────────────────────── */
        if (action === "board") {
          const { reviews, malformed } = await loadAllReviews();
          const byLane = new Map<string, ReturnType<typeof toCard>[]>();
          for (const lane of LANES) byLane.set(lane.id, []);
          for (const review of reviews) {
            byLane.get(laneOf(review))!.push(toCard(review));
          }
          const columns = LANES.map((lane) => ({
            id: lane.id,
            title: lane.title,
            cards: byLane.get(lane.id)!,
          }));
          const malformedNote = malformed > 0 ? ` (${malformed} malformed record(s) skipped)` : "";
          return {
            status: "ok",
            message: `Nightly PR review: ${reviews.length} card(s)${malformedNote}`,
            data: { reviewed: reviews.length, malformed },
            view: contract(
              "kanban",
              "Nightly PR Review",
              { columns },
              { source: "hwc_nightly_review", reviewed: reviews.length },
            ),
          };
        }

        /* ── detail ─────────────────────────────────────────────── */
        if (action === "detail") {
          const id = args.id as string | undefined;
          if (!id) {
            return mcpError({ type: "VALIDATION_ERROR", message: "id is required for action=detail" });
          }
          const review = await loadReview(id);
          if (!review) {
            return mcpError({ type: "NOT_FOUND", message: `No review found for id '${id}'`, suggestion: "Use action=board to list available review ids", context: { id } });
          }
          const lines = [
            `# ${review.title}`,
            `goal: ${review.goal}  ·  verdict: ${review.verdict}  ·  status: ${review.status}`,
            review.prUrl ? `PR: ${review.prUrl}` : "PR: (none)",
            "",
            "## What was done",
            review.whatWasDone,
            "",
            "## What it means",
            review.whatItMeans,
            "",
            "## Recommendation",
            review.recommendation,
            "",
            `## Risks (${review.risks.length})`,
            ...(review.risks.length ? review.risks.map((r) => `- ${r}`) : ["- (none)"]),
            "",
            `## Commits (${review.commits.length})`,
            ...(review.commits.length ? review.commits.map((c) => `- ${c}`) : ["- (none)"]),
          ];
          return {
            status: "ok",
            message: `Review ${review.id}: ${review.verdict} (${review.status})`,
            data: review,
            view: contract(
              "text",
              review.title,
              { summary: review.recommendation, body: lines.join("\n") },
              { source: "hwc_nightly_review", id: review.id, verdict: review.verdict, status: review.status },
            ),
          };
        }

        /* ── merge ──────────────────────────────────────────────── */
        if (action === "merge") {
          try {
            const id = args.id as string | undefined;
            if (!id) {
              return mcpError({ type: "VALIDATION_ERROR", message: "id is required for action=merge" });
            }
            const method = (args.method as string) || "squash";
            if (!["squash", "merge", "rebuild"].includes(method)) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid method '${method}'`, suggestion: "Use squash, merge, or rebuild" });
            }
            const review = await loadReview(id);
            if (!review) {
              return mcpError({ type: "NOT_FOUND", message: `No review found for id '${id}'`, suggestion: "Use action=board to list available review ids", context: { id } });
            }
            if (review.prNumber == null) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Review '${id}' has no prNumber — nothing to merge`, suggestion: "Only cards that opened a PR can be merged", context: { id } });
            }
            const slug = repoSlug(review.repo);
            if (!slug) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Cannot derive owner/name from repo '${review.repo}'`, suggestion: "The review's repo must be a github URL or owner/name slug for gh -R", context: { repo: review.repo } });
            }
            const ghArgs = ["pr", "merge", String(review.prNumber), `--${method}`, "-R", slug];
            const res = await gh(ghArgs);
            if (res.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: `gh pr merge failed for PR #${review.prNumber}`, error: res.stderr.slice(0, 500), suggestion: "Check the PR is mergeable, gh is authenticated, and the branch is not protected", context: { command: `gh ${ghArgs.join(" ")}`, exitCode: res.exitCode } });
            }
            review.status = "merged";
            await saveReview(review);
            return {
              status: "ok",
              message: `Merged PR #${review.prNumber} (${method}) for ${review.goal}/${review.cardSlug}`,
              data: { id: review.id, prNumber: review.prNumber, method, repo: slug, status: review.status },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Merge failed", err, "Is gh on PATH and authenticated?");
          }
        }

        /* ── requeue ────────────────────────────────────────────── */
        if (action === "requeue") {
          try {
            const id = args.id as string | undefined;
            if (!id) {
              return mcpError({ type: "VALIDATION_ERROR", message: "id is required for action=requeue" });
            }
            const review = await loadReview(id);
            if (!review) {
              return mcpError({ type: "NOT_FOUND", message: `No review found for id '${id}'`, suggestion: "Use action=board to list available review ids", context: { id } });
            }
            // Flip the source card back to queued (the queue gate). Hard fail if
            // the card is gone — requeue without re-queuing the card is a no-op
            // the user would mistake for success.
            const flipped = await setCardQueued(review.goal, review.cardSlug);
            if (!flipped) {
              return mcpError({ type: "NOT_FOUND", message: `Source card not found: _inbox/nightly_builds/${review.goal}/${review.cardSlug}.md`, suggestion: "The card may have been moved or renamed; cannot re-queue", context: { goal: review.goal, cardSlug: review.cardSlug } });
            }
            // Best-effort close the PR if one exists — non-fatal on failure.
            let prClosed: boolean | null = null;
            if (review.prNumber != null) {
              const slug = repoSlug(review.repo);
              if (slug) {
                const res = await gh(["pr", "close", String(review.prNumber), "-R", slug]);
                prClosed = res.exitCode === 0;
              }
            }
            review.status = "requeued";
            await saveReview(review);
            return {
              status: "ok",
              message: `Re-queued ${review.goal}/${review.cardSlug} (card → queued${prClosed === true ? ", PR closed" : prClosed === false ? ", PR close failed" : ""})`,
              data: { id: review.id, cardQueued: true, prClosed, status: review.status },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Requeue failed", err, "Check vault write access and gh availability");
          }
        }

        /* ── rebuild ────────────────────────────────────────────── */
        if (action === "rebuild") {
          try {
            const host = (args.host as string) || "hwc-server";
            await mkdir(REBUILD_DIR, { recursive: true });
            await writeFile(join(REBUILD_DIR, host), `${host}\n`, "utf-8");
            return {
              status: "ok",
              message: `Rebuild requested for ${host}`,
              data: {
                host,
                spool: join(REBUILD_DIR, host),
                note: "A privileged unit consumes this spool and runs the rebuild; this tool does not run nixos-rebuild.",
              },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Rebuild request failed", err, "Check write access to /var/lib/refinery/rebuild-request");
          }
        }

        return mcpError({ type: "VALIDATION_ERROR", message: `Unknown action: ${action}`, suggestion: "Use board, detail, merge, requeue, or rebuild" });
      },
    },
  ];
}
