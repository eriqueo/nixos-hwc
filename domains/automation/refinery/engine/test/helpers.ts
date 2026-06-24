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
export const fixedClock = () => `2026-06-15T00:00:${String(tick++).padStart(2, "0")}Z`;
export function resetClock() {
  tick = 0;
}
