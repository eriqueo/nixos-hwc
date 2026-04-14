/**
 * TTL cache for expensive queries (nix eval, podman stats, systemctl).
 * Prevents repeated slow commands within the TTL window.
 */

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

export class TtlCache {
  private cache = new Map<string, CacheEntry<unknown>>();

  /** Get a cached value, or undefined if expired/missing */
  get<T>(key: string): T | undefined {
    const entry = this.cache.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) {
      this.cache.delete(key);
      return undefined;
    }
    return entry.value as T;
  }

  /** Set a value with TTL in seconds */
  set<T>(key: string, value: T, ttlSeconds: number): void {
    this.cache.set(key, {
      value,
      expiresAt: Date.now() + ttlSeconds * 1000,
    });
  }

  /** Get or compute: returns cached value if fresh, otherwise calls fn and caches result */
  async getOrCompute<T>(key: string, ttlSeconds: number, fn: () => Promise<T>): Promise<T> {
    const cached = this.get<T>(key);
    if (cached !== undefined) return cached;
    const value = await fn();
    this.set(key, value, ttlSeconds);
    return value;
  }

  /** Invalidate a specific key */
  invalidate(key: string): void {
    this.cache.delete(key);
  }

  /** Clear all cached entries */
  clear(): void {
    this.cache.clear();
  }

  /** Number of active (non-expired) entries */
  size(): number {
    // Lazy cleanup
    const now = Date.now();
    for (const [key, entry] of this.cache) {
      if (now > entry.expiresAt) this.cache.delete(key);
    }
    return this.cache.size;
  }
}
