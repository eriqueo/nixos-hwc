/** Read-only I/O scheduling. shell.ts owns command execution, not read scheduling. */
export const READ_CONCURRENCY = 8;

/**
 * At most READ_CONCURRENCY reads run per invocation; excess items wait in input
 * order. Results retain that order. On failure, stop admitting work, drain the
 * active reads, then throw the first error. Callers own per-item degradation.
 * Keep recursive traversal outside this pool so nested pools cannot multiply it.
 */
export async function mapReads<T, R>(
  items: readonly T[],
  read: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  let failed = false;
  let failure: unknown;
  async function worker(): Promise<void> {
    while (!failed && next < items.length) {
      const index = next++;
      try {
        results[index] = await read(items[index], index);
      } catch (err) {
        if (!failed) { failed = true; failure = err; }
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(READ_CONCURRENCY, items.length) }, worker));
  if (failed) throw failure;
  return results;
}
