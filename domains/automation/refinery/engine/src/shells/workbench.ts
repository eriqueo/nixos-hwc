// Workbench registry for the Refinery board shell. NixOS (hwc.business.workbench)
// is the one producer of the area list; the board receives the rendered
// areas.json path through REFINERY_WORKBENCH_AREAS_FILE and parses it ONCE at
// startup, at the edge. A missing or malformed file degrades to "registry
// unavailable": the switcher still offers Refinery and the Workbench home, so
// the board never depends on the registry to render.
import { readFileSync } from "node:fs";

export interface WorkbenchArea {
  id: string;
  label: string;
  available: boolean;
  href: string | null;
}
export interface WorkbenchRegistry {
  product: string;
  home: string;
  areas: WorkbenchArea[];
}

// Same fallback every other area uses when the registry cannot be read.
export const WORKBENCH_HOME = "https://workbench.hwc.iheartwoodcraft.com/";
export const REFINERY_AREA_ID = "refinery";

export function parseWorkbenchRegistry(input: unknown): WorkbenchRegistry {
  if (!input || typeof input !== "object") throw new Error("registry: not an object");
  const o = input as Record<string, unknown>;
  if (typeof o.home !== "string" || !Array.isArray(o.areas)) throw new Error("registry: missing home/areas");
  const seen = new Set<string>();
  const areas = o.areas.map((raw): WorkbenchArea => {
    const a = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
    if (typeof a.id !== "string" || typeof a.label !== "string" || typeof a.available !== "boolean")
      throw new Error("registry: malformed area");
    if (a.href !== null && typeof a.href !== "string") throw new Error(`registry: bad href for ${a.id}`);
    if (seen.has(a.id)) throw new Error(`registry: duplicate id ${a.id}`);
    seen.add(a.id);
    return { id: a.id, label: a.label, available: a.available, href: a.href as string | null };
  });
  return { product: typeof o.product === "string" ? o.product : "HWC Workbench", home: o.home, areas };
}

export function loadWorkbenchRegistry(file: string | undefined, warn: (msg: string) => void = console.warn): WorkbenchRegistry | null {
  if (!file) return null;
  try {
    return parseWorkbenchRegistry(JSON.parse(readFileSync(file, "utf8")));
  } catch (err) {
    warn(`[workbench] registry unavailable (${file}): ${(err as Error).message}`);
    return null;
  }
}
