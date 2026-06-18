// A filesystem ReviewsStore: persists each PrReview as one JSON file under a
// directory, named "<safeReviewId(id)>.json". Mirrors markdown-store.ts: the
// stored bytes are the canonical contract, validated with PrReviewSchema on
// load so save→load is exact regardless of who wrote the file. The directory is
// late-bound (env REFINERY_REVIEWS_DIR, default /var/lib/refinery/reviews).

import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { PrReview, PrReviewSchema, safeReviewId } from "../review/contract.js";
import { ReviewsStore } from "../review/ports.js";

export const DEFAULT_REVIEWS_DIR = "/var/lib/refinery/reviews";

/** Resolve the reviews dir from an explicit value, the env, or the default. */
export function resolveReviewsDir(dir?: string): string {
  return dir ?? process.env.REFINERY_REVIEWS_DIR ?? DEFAULT_REVIEWS_DIR;
}

export class FileReviewsStore implements ReviewsStore {
  constructor(private readonly dir: string = resolveReviewsDir()) {
    mkdirSync(this.dir, { recursive: true });
  }

  private pathFor(id: string): string {
    return join(this.dir, `${safeReviewId(id)}.json`);
  }

  async save(r: PrReview): Promise<void> {
    const valid = PrReviewSchema.parse(r);
    writeFileSync(this.pathFor(valid.id), JSON.stringify(valid, null, 2));
  }

  async load(id: string): Promise<PrReview | null> {
    const path = this.pathFor(id);
    if (!existsSync(path)) return null;
    return PrReviewSchema.parse(JSON.parse(readFileSync(path, "utf8")));
  }

  async list(): Promise<PrReview[]> {
    if (!existsSync(this.dir)) return [];
    const out: PrReview[] = [];
    for (const f of readdirSync(this.dir)) {
      if (!f.endsWith(".json")) continue;
      out.push(PrReviewSchema.parse(JSON.parse(readFileSync(join(this.dir, f), "utf8"))));
    }
    return out;
  }

  async delete(id: string): Promise<void> {
    const path = this.pathFor(id);
    if (existsSync(path)) rmSync(path);
  }
}
