/**
 * Sliding-window rate limiter — in-memory, transport-layer.
 *
 * Keyed by the validated LeadInput.source field ("calculator",
 * "contact", "appointment"). Each source gets an independent window.
 *
 * Why not in core/: this is a transport concern, not domain logic. A
 * batch importer hitting hwc-leads directly (e.g., a one-shot CSV
 * replay) might legitimately exceed the per-source budget — the limit
 * exists to absorb misconfigured n8n retry loops + webhook replay
 * storms at the HTTP boundary, not to enforce a business invariant.
 *
 * State is per-process (a Map). On service restart every window
 * resets — acceptable because real spam patterns survive minutes, not
 * seconds, and restarts are rare. No external deps; pruning is
 * amortised on each check.
 */

export interface RateLimitConfig {
  /** Max requests per key per window. */
  readonly maxPerWindow: number;
  /** Window length in seconds. */
  readonly windowSeconds: number;
}

export interface RateLimitOk {
  readonly ok: true;
  readonly count: number;
  readonly remaining: number;
}

export interface RateLimitDenied {
  readonly ok: false;
  readonly count: number;
  readonly retryAfterSeconds: number;
}

export type RateLimitResult = RateLimitOk | RateLimitDenied;

export class RateLimiter {
  private readonly windowMs: number;
  private readonly buckets: Map<string, number[]> = new Map();

  constructor(private readonly config: RateLimitConfig) {
    this.windowMs = config.windowSeconds * 1000;
  }

  /**
   * Records an attempt for `key` and returns whether it's allowed.
   * Prunes expired timestamps from the bucket on each call — keeps
   * memory bounded without a separate sweep loop.
   *
   * `now` is injectable for tests; production passes Date.now().
   */
  check(key: string, now: number = Date.now()): RateLimitResult {
    const cutoff = now - this.windowMs;
    const existing = this.buckets.get(key) ?? [];
    const pruned = existing.filter((ts) => ts > cutoff);

    if (pruned.length >= this.config.maxPerWindow) {
      // Denied — earliest surviving timestamp tells us when the bucket
      // will have room again.
      const earliest = pruned[0] ?? now;
      const retryAfterMs = Math.max(0, earliest + this.windowMs - now);
      this.buckets.set(key, pruned);
      return {
        ok: false,
        count: pruned.length,
        retryAfterSeconds: Math.ceil(retryAfterMs / 1000),
      };
    }

    pruned.push(now);
    this.buckets.set(key, pruned);
    return {
      ok: true,
      count: pruned.length,
      remaining: this.config.maxPerWindow - pruned.length,
    };
  }
}
