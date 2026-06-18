// The morning PR-review integration contract. After the 01:30 nightly run
// pushes a branch per finished card (but never opens a PR), the morning review
// pass opens the PR, judges the branch, and writes one PrReview JSON per card.
// This file is the single source of truth every other surface reads: the CLI
// emits it, the ReviewsStore persists it, the board/notifier consume it.
//
// Contracts-first: the shape is a Zod schema; anything crossing the trust
// boundary (LLM output, stored JSON, gh output) is parsed before core touches
// it. `whatWasDone` / `whatItMeans` / `recommendation` are the human-judgement
// fields the LLM fills; the rest are git/GitHub facts the orchestrator gathers.

import { z } from "zod";

export const DiffstatSchema = z.object({
  files: z.number().int().nonnegative(),
  insertions: z.number().int().nonnegative(),
  deletions: z.number().int().nonnegative(),
});
export type Diffstat = z.infer<typeof DiffstatSchema>;

export const ReviewVerdictTokenSchema = z.enum(["merge-ready", "needs-work", "reject"]);
export type ReviewVerdictToken = z.infer<typeof ReviewVerdictTokenSchema>;

export const ReviewStatusSchema = z.enum([
  "needs-you",
  "merged",
  "requeued",
  "rejected",
]);
export type ReviewStatus = z.infer<typeof ReviewStatusSchema>;

export const PrReviewSchema = z.object({
  id: z.string().min(1), // "<goal>/<cardSlug>"
  goal: z.string().min(1),
  cardSlug: z.string().min(1),
  title: z.string().min(1),
  repo: z.string().min(1),
  branch: z.string().min(1),
  base: z.string().min(1),
  prUrl: z.string().nullable(),
  prNumber: z.number().int().nullable(),
  reviewedAt: z.string().min(1),
  verdict: ReviewVerdictTokenSchema,
  mergeable: z.boolean().nullable(),
  diffstat: DiffstatSchema,
  commits: z.array(z.string()),
  whatWasDone: z.string(),
  whatItMeans: z.string(),
  recommendation: z.string(),
  risks: z.array(z.string()),
  status: ReviewStatusSchema.default("needs-you"),
  reportRelPath: z.string().nullable(),
});
export type PrReview = z.infer<typeof PrReviewSchema>;

/**
 * Sanitize a review id ("<goal>/<slug>") into a filename-safe token: "/" and
 * any character outside [A-Za-z0-9._-] collapse to "-". Used by the filesystem
 * ReviewsStore to map an id → "<safeReviewId(id)>.json".
 */
export function safeReviewId(id: string): string {
  return id.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "review";
}
