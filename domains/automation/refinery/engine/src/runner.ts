import {
  GateModule,
  Item,
  ItemStore,
  Profile,
} from "./contracts.js";
import { UnknownGateError, UnknownPhaseError } from "./errors.js";

export type Clock = () => string;
const defaultClock: Clock = () => new Date().toISOString();

export interface RunnerDeps {
  store: ItemStore;
  clock?: Clock;
}

export interface RunPassResult {
  item: Item;
  ran: string[];
  stoppedBy?: { phase: string; reason: "parked" | "failed" };
}

function indexGates(profile: Profile, gates: GateModule[]): GateModule[] {
  const byId = new Map(gates.map((g) => [g.id, g]));
  return profile.gates.map((id) => {
    const g = byId.get(id);
    if (!g) throw new UnknownGateError(id);
    return g;
  });
}

function startIndex(ordered: GateModule[], phase: string): number {
  const idx = ordered.findIndex((g) => g.id === phase);
  if (idx === -1) throw new UnknownPhaseError(phase);
  return idx;
}

export async function runPass(
  itemIn: Item,
  profile: Profile,
  gates: GateModule[],
  deps: RunnerDeps,
): Promise<RunPassResult> {
  const clock = deps.clock ?? defaultClock;
  const ordered = indexGates(profile, gates);
  let item: Item = {
    ...itemIn,
    history: [...itemIn.history],
  };
  const ran: string[] = [];

  let i = startIndex(ordered, item.phase);
  for (; i < ordered.length; i++) {
    const gate = ordered[i]!;
    if (!gate.applies(item)) continue;
    item = {
      ...item,
      phase: gate.id,
      phaseStatus: "pending",
      parkedReason: undefined,
    };
    ran.push(gate.id);
    const verdict = await gate.run(item);
    const decision = gate.decide(verdict);
    if (decision === "pass") {
      item = {
        ...item,
        phaseStatus: "passed",
        parkedReason: undefined,
        history: [
          ...item.history,
          { phase: gate.id, status: "passed", at: clock() },
        ],
      };
      continue;
    }
    const status = decision === "park" ? "parked" : "failed";
    const reason =
      typeof verdict.verdict === "string" ? verdict.verdict : decision;
    item = {
      ...item,
      phaseStatus: status,
      parkedReason: reason,
      history: [
        ...item.history,
        { phase: gate.id, status, at: clock(), note: reason },
      ],
    };
    await deps.store.save(item);
    return { item, ran, stoppedBy: { phase: gate.id, reason: status } };
  }
  await deps.store.save(item);
  return { item, ran };
}

export interface RewindOpts {
  clock?: Clock;
  // When given, rewind validates that toPhase is one of the profile's gates
  // and throws UnknownPhaseError at the call site instead of deferring the
  // failure to the next runPass.
  profile?: Profile;
}

export function rewind(
  item: Item,
  toPhase: string,
  note: string,
  opts: RewindOpts = {},
): Item {
  const clock = opts.clock ?? defaultClock;
  if (opts.profile && !opts.profile.gates.includes(toPhase)) {
    throw new UnknownPhaseError(toPhase);
  }
  return {
    ...item,
    phase: toPhase,
    phaseStatus: "pending",
    parkedReason: undefined,
    history: [
      ...item.history,
      { phase: toPhase, status: "rewound", at: clock(), note },
    ],
  };
}
