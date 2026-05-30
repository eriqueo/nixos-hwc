import type { Chunk } from "./chunking.ts";

export interface ScoredChunk extends Chunk {
  score: number;     // cosine similarity, [-1, 1]
}

/** Dot product of two equal-length Float32Arrays. */
export function dot(a: Float32Array, b: Float32Array): number {
  let s = 0;
  for (let i = 0; i < a.length; i++) s += a[i] * b[i];
  return s;
}

/** L2 norm. */
export function norm(a: Float32Array): number {
  let s = 0;
  for (let i = 0; i < a.length; i++) s += a[i] * a[i];
  return Math.sqrt(s);
}

/** Cosine similarity. Inputs assumed non-zero. */
export function cosine(a: Float32Array, b: Float32Array): number {
  const na = norm(a);
  const nb = norm(b);
  if (na === 0 || nb === 0) return 0;
  return dot(a, b) / (na * nb);
}

/**
 * Brute-force top-K cosine. Vault-scale (~thousands) so <10ms in V8.
 * Returns chunks ordered by descending score.
 *
 * Frontmatter chunks are score-down-weighted by 0.5 (metadata is low-value
 * signal compared to prose).
 */
export function rankTopK(
  queryVec: Float32Array,
  candidates: Iterable<{ chunk: Chunk; vec: Float32Array }>,
  k: number,
): ScoredChunk[] {
  const scored: ScoredChunk[] = [];
  for (const { chunk, vec } of candidates) {
    let s = cosine(queryVec, vec);
    if (chunk.kind === "frontmatter") s *= 0.5;
    scored.push({ ...chunk, score: s });
  }
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, k);
}
