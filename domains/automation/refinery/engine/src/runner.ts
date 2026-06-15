import {
  GateModule,
  Item,
  ItemStore,
  Manifest,
} from "./contracts.js";
import { UnknownGateError, UnknownStageError } from "./errors.js";

export type Clock = () => string;
const defaultClock: Clock = () => new Date().toISOString();

export interface RunnerDeps {
  store: ItemStore;
  clock?: Clock;
}

export interface RunPassResult {
  item: Item;
  ran: string[];
  stoppedBy?: { stage: string; reason: "parked" | "failed" };
}

function indexGates(manifest: Manifest, gates: GateModule[]): GateModule[] {
  const byId = new Map(gates.map((g) => [g.id, g]));
  return manifest.gates.map((id) => {
    const g = byId.get(id);
    if (!g) throw new UnknownGateError(id);
    return g;
  });
}

function startIndex(ordered: GateModule[], stage: string): number {
  const idx = ordered.findIndex((g) => g.id === stage);
  if (idx === -1) throw new UnknownStageError(stage);
  return idx;
}

export async function runPass(
  itemIn: Item,
  manifest: Manifest,
  gates: GateModule[],
  deps: RunnerDeps,
): Promise<RunPassResult> {
  const clock = deps.clock ?? defaultClock;
  const ordered = indexGates(manifest, gates);
  let item: Item = {
    ...itemIn,
    history: [...itemIn.history],
  };
  const ran: string[] = [];

  let i = startIndex(ordered, item.stage);
  for (; i < ordered.length; i++) {
    const gate = ordered[i]!;
    if (!gate.applies(item)) continue;
    item = {
      ...item,
      stage: gate.id,
      stageStatus: "pending",
      parkedReason: undefined,
    };
    ran.push(gate.id);
    const verdict = await gate.run(item);
    const decision = gate.decide(verdict);
    if (decision === "pass") {
      item = {
        ...item,
        stageStatus: "passed",
        parkedReason: undefined,
        history: [
          ...item.history,
          { stage: gate.id, status: "passed", at: clock() },
        ],
      };
      continue;
    }
    const status = decision === "park" ? "parked" : "failed";
    const reason =
      typeof verdict.verdict === "string" ? verdict.verdict : decision;
    item = {
      ...item,
      stageStatus: status,
      parkedReason: reason,
      history: [
        ...item.history,
        { stage: gate.id, status, at: clock(), note: reason },
      ],
    };
    await deps.store.save(item);
    return { item, ran, stoppedBy: { stage: gate.id, reason: status } };
  }
  await deps.store.save(item);
  return { item, ran };
}

export interface RewindOpts {
  clock?: Clock;
  // When given, rewind validates that toStage is one of the manifest's gates
  // and throws UnknownStageError at the call site instead of deferring the
  // failure to the next runPass.
  manifest?: Manifest;
}

export function rewind(
  item: Item,
  toStage: string,
  note: string,
  opts: RewindOpts = {},
): Item {
  const clock = opts.clock ?? defaultClock;
  if (opts.manifest && !opts.manifest.gates.includes(toStage)) {
    throw new UnknownStageError(toStage);
  }
  return {
    ...item,
    stage: toStage,
    stageStatus: "pending",
    parkedReason: undefined,
    history: [
      ...item.history,
      { stage: toStage, status: "rewound", at: clock(), note },
    ],
  };
}
