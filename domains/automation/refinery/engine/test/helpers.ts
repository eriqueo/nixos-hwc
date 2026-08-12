import {
  GateDecision,
  GateModule,
  GateVerdict,
  Item,
} from "../src/contracts.js";

export interface StubOpts {
  id: string;
  decision?: GateDecision;
  verdictLabel?: string;
  applies?: (item: Item) => boolean;
  onRun?: (item: Item) => void;
}

export function stubGate(opts: StubOpts): GateModule {
  const decision = opts.decision ?? "pass";
  const label = opts.verdictLabel ?? decision;
  return {
    id: opts.id,
    applies: opts.applies ?? (() => true),
    async run(item: Item): Promise<GateVerdict> {
      opts.onRun?.(item);
      return { verdict: label, output: { stub: opts.id } };
    },
    decide(): GateDecision {
      return decision;
    },
  };
}

export function makeItem(overrides: Partial<Item> = {}): Item {
  return {
    id: "item-1",
    pipeline: "test-pipeline",
    step: "g1",
    state: "pending",
    payload: { hello: "world" },
    history: [],
    ...overrides,
  };
}

let tick = 0;
// Monotonic test clock: one second per call from a fixed base.
//
// This used to interpolate the counter straight into the seconds field
// (`00:00:${tick}`), which silently produced INVALID timestamps past 60 ticks —
// "2026-06-15T00:00:60Z" parses to NaN. Any code doing date math on the clock
// (sweepArchive's aged-out check) then failed closed, and which tests broke
// depended on how many clock calls earlier tests happened to make. Deriving
// from an epoch keeps every tick a real instant, however many are consumed.
const CLOCK_BASE_MS = Date.parse("2026-06-15T00:00:00Z");
export const fixedClock = () =>
  new Date(CLOCK_BASE_MS + tick++ * 1000).toISOString().replace(".000Z", "Z");
export function resetClock() {
  tick = 0;
}
