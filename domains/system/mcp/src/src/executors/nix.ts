/**
 * Nix evaluation executor — wraps nix eval and nix flake commands with caching.
 *
 * IMPORTANT: nix eval evaluates from the git store, not the working tree.
 * Uncommitted changes won't be reflected. The tools note this in results.
 */

import { safeExec } from "./shell.js";
import { TtlCache } from "../cache.js";
import { log } from "../log.js";

const cache = new TtlCache();

/**
 * Evaluate a Nix expression against a flake's nixosConfiguration.
 * Returns the JSON-parsed result.
 */
export async function nixEval(
  flakePath: string,
  host: string,
  attrPath: string,
  ttlSeconds: number = 300
): Promise<unknown> {
  const cacheKey = `nix-eval:${host}:${attrPath}`;

  return cache.getOrCompute(cacheKey, ttlSeconds, async () => {
    const fullAttr = `.#nixosConfigurations.${host}.config.${attrPath}`;
    log.debug("nix eval", { flakePath, fullAttr });

    const result = await safeExec("nix", [
      "eval",
      fullAttr,
      "--json",
      "--no-write-lock-file",
    ], { timeout: 30000, maxBuffer: 5 * 1024 * 1024 });

    if (result.exitCode !== 0) {
      throw new Error(`nix eval failed: ${result.stderr.slice(0, 500)}`);
    }

    return JSON.parse(result.stdout);
  });
}

/**
 * Get flake metadata (inputs, revisions, lock file age).
 */
export async function flakeMetadata(
  _flakePath: string,
  ttlSeconds: number = 300
): Promise<Record<string, unknown>> {
  const cacheKey = "flake-metadata";

  return cache.getOrCompute(cacheKey, ttlSeconds, async () => {
    const result = await safeExec("nix", [
      "flake",
      "metadata",
      "--json",
      "--no-write-lock-file",
    ], { timeout: 30000 });

    if (result.exitCode !== 0) {
      throw new Error(`nix flake metadata failed: ${result.stderr.slice(0, 500)}`);
    }

    return JSON.parse(result.stdout);
  });
}

/**
 * Invalidate all cached nix evaluation results.
 */
export function invalidateNixCache(): void {
  cache.clear();
}
