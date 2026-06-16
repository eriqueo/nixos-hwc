// Gauntlet registry — disk catalog of gauntlet contracts, mirroring how
// ProfileCatalog loads profiles/*.yaml. A profile that dispatches names its
// gauntlet by id; this resolves that id to a contract.

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { GauntletContract, parseGauntletContract } from "./contract.js";

/** Scan a directory of <id>.yaml gauntlet contracts, parse+validate, key by id. */
export function loadGauntlets(dir: string): Map<string, GauntletContract> {
  const out = new Map<string, GauntletContract>();
  for (const f of readdirSync(dir)) {
    if (!f.endsWith(".yaml") && !f.endsWith(".yml")) continue;
    const contract = parseGauntletContract(readFileSync(join(dir, f), "utf8"));
    out.set(contract.id, contract);
  }
  return out;
}

export function getGauntlet(
  map: Map<string, GauntletContract>,
  id: string,
): GauntletContract | null {
  return map.get(id) ?? null;
}
