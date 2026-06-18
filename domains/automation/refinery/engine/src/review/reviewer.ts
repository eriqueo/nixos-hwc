// PURE core: judge one autonomous-agent branch. Given the git/GitHub facts the
// orchestrator already gathered, prompt the LlmPort for the human-judgement
// fields, parse the LLM JSON at the trust boundary with Zod (parseVerdict-style,
// reusing the shared verdict parser), and assemble a PrReview.
//
// This function does NOT open a PR or touch git — prUrl/prNumber stay null and
// status defaults to "needs-you"; opening the PR + filling those is run.ts's
// job. Hexagonal: the only outbound dependency is the LlmPort.

import { z } from "zod";
import { LlmPort } from "../gates/llm-port.js";
import { parseVerdict } from "../gates/verdict.js";
import {
  PrReview,
  PrReviewSchema,
  Diffstat,
  ReviewVerdictTokenSchema,
} from "./contract.js";

/** The shape the LLM must return — the human-judgement subset of a PrReview. */
export const ReviewVerdictSchema = z.object({
  verdict: ReviewVerdictTokenSchema,
  whatWasDone: z.string().min(1),
  whatItMeans: z.string().min(1),
  recommendation: z.string().min(1),
  risks: z.array(z.string()),
});
export type ReviewVerdict = z.infer<typeof ReviewVerdictSchema>;

export interface ReviewInput {
  id: string;
  goal: string;
  cardSlug: string;
  title: string;
  repo: string;
  branch: string;
  base: string;
  diffstat: Diffstat;
  commits: string[];
  mergeable: boolean | null;
  reportText: string | null;
  cardBody: string;
  reportRelPath?: string | null;
  reviewedAt?: string;
}

const REVIEW_PROMPT = (input: ReviewInput): string =>
  [
    "You are reviewing the branch produced overnight by an AUTONOMOUS coding agent.",
    "Be skeptical: the agent runs unsupervised, so fake-green tests (assertions that",
    "always pass, suites that exit 0 regardless), unrelated file churn, scope creep,",
    "or a branch that does not match its stated goal must drag the verdict down to",
    '"needs-work" or "reject". Only "merge-ready" if the diff cleanly does what the',
    "card asked and you would merge it yourself.",
    "",
    "Classify `verdict` as one of: merge-ready | needs-work | reject.",
    "`whatWasDone`: 1-3 plain sentences describing what the branch actually changed.",
    "`whatItMeans`: the impact/consequence for the human owner if this is merged.",
    "`recommendation`: an action — 'merge now' / 'fix X then merge' / 'send back because Y'.",
    "`risks`: array of concrete risks (empty array if genuinely none).",
    "",
    `Card goal: ${input.goal} / ${input.cardSlug}`,
    `Title: ${input.title}`,
    `Repo: ${input.repo}   Branch: ${input.branch}   Base: ${input.base}`,
    `Mergeable (clean merge, no conflicts): ${input.mergeable === null ? "unknown" : input.mergeable}`,
    `Diffstat: ${input.diffstat.files} files, +${input.diffstat.insertions} / -${input.diffstat.deletions}`,
    "Commits:",
    input.commits.length ? input.commits.map((c) => `- ${c}`).join("\n") : "- (none)",
    "",
    "Card body:",
    "```",
    input.cardBody || "(empty)",
    "```",
    "",
    "Agent's REPORT.md (its own account of the run — corroborate against the diff, do not trust blindly):",
    "```",
    input.reportText ?? "(no REPORT.md present)",
    "```",
    "",
    "Respond with ONLY a JSON object of this shape:",
    '{"verdict":"merge-ready|needs-work|reject","whatWasDone":"...","whatItMeans":"...","recommendation":"...","risks":["..."]}',
  ].join("\n");

/**
 * Judge one branch. Prompts the LLM, parses its verdict at the boundary, and
 * returns a fully-validated PrReview (prUrl/prNumber null, status "needs-you").
 */
export async function reviewBranch(input: ReviewInput, llm: LlmPort): Promise<PrReview> {
  const raw = await llm.complete(REVIEW_PROMPT(input));
  const v = parseVerdict(raw, ReviewVerdictSchema, `review:${input.id}`);

  const review: PrReview = {
    id: input.id,
    goal: input.goal,
    cardSlug: input.cardSlug,
    title: input.title,
    repo: input.repo,
    branch: input.branch,
    base: input.base,
    prUrl: null,
    prNumber: null,
    reviewedAt: input.reviewedAt ?? new Date().toISOString(),
    verdict: v.verdict,
    mergeable: input.mergeable,
    diffstat: input.diffstat,
    commits: input.commits,
    whatWasDone: v.whatWasDone,
    whatItMeans: v.whatItMeans,
    recommendation: v.recommendation,
    risks: v.risks,
    status: "needs-you",
    reportRelPath: input.reportRelPath ?? null,
  };
  // Re-validate the assembled record (fail loud if a field drifted).
  return PrReviewSchema.parse(review);
}
