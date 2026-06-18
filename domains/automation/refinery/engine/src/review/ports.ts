// Outbound ports for the morning PR-review pass. Mirrors effectors/ports.ts:
// every side-effecting operation (git facts, GitHub PR lifecycle, review
// persistence) is an interface so the core (reviewer.ts + run.ts) is pure
// control flow — tests inject stubs and no real git/gh/llm is ever spawned.
// Concrete adapters live in ../adapters (git-facts.ts, github-cli.ts) and
// ../stores (reviews-store.ts). The LlmPort the reviewer consults is the
// existing engine port (../gates/llm-port.js) — not redefined here.

import { PrReview, Diffstat } from "./contract.js";

/** Read-only git facts about a pushed branch relative to its base. */
export interface GitFactsPort {
  /** Fetch origin; return the base ref to compare against ("origin/main"). */
  resolveBase(repo: string): Promise<string>;
  /** `git diff --shortstat base..branch` → file/line counts. */
  diffstat(opts: { repo: string; base: string; branch: string }): Promise<Diffstat>;
  /** `git log --oneline base..branch` → commit subjects (newest first). */
  commits(opts: { repo: string; base: string; branch: string }): Promise<string[]>;
  /** Would base + branch merge cleanly (no conflicts)? `git merge-tree` dry check. */
  isMergeable(opts: { repo: string; base: string; branch: string }): Promise<boolean>;
}

/** The GitHub PR lifecycle (shelled to `gh` in production). */
export interface GitHubPort {
  /** Open a PR for an already-pushed branch. Returns its url + number. */
  createPr(opts: {
    repo: string;
    base: string;
    branch: string;
    title: string;
    body: string;
  }): Promise<{ url: string; number: number }>;
  /** Merge a PR with the chosen method. */
  mergePr(opts: { repo: string; number: number; method: "squash" | "merge" | "rebase" }): Promise<void>;
  /** Close a PR without merging. */
  closePr(opts: { repo: string; number: number }): Promise<void>;
  /** The open PR for this branch, if one already exists (so re-runs don't double-open). */
  existingPr(opts: { repo: string; branch: string }): Promise<{ url: string; number: number } | null>;
}

/** Persistence for review records — same load/save/list/delete shape as ItemStore. */
export interface ReviewsStore {
  save(r: PrReview): Promise<void>;
  load(id: string): Promise<PrReview | null>;
  list(): Promise<PrReview[]>;
  delete(id: string): Promise<void>;
}
