import {
  GateModule,
  Item,
  ItemStore,
  Pipeline,
} from "./contracts.js";
import { UnknownGateError, UnknownStepError } from "./errors.js";

export type Clock = () => string;
const defaultClock: Clock = () => new Date().toISOString();

export interface RunnerDeps {
  store: ItemStore;
  clock?: Clock;
}

export interface RunPassResult {
  item: Item;
  ran: string[];
  stoppedBy?: { step: string; reason: "parked" | "failed" };
}

function indexGates(pipeline: Pipeline, gates: GateModule[]): GateModule[] {
  const byId = new Map(gates.map((g) => [g.id, g]));
  return pipeline.gates.map((id) => {
    const g = byId.get(id);
    if (!g) throw new UnknownGateError(id);
    return g;
  });
}

function startIndex(ordered: GateModule[], step: string): number {
  const idx = ordered.findIndex((g) => g.id === step);
  if (idx === -1) throw new UnknownStepError(step);
  return idx;
}

// Merge a gate's verdict into payload.verdicts[step] (non-destructive). Only
// applies when the payload is an object (engine items always are); a non-object
// payload is returned unchanged so nothing is lost.
function withVerdict(
  payload: unknown,
  step: string,
  decision: string,
  reason: string,
  output: unknown,
): unknown {
  if (!payload || typeof payload !== "object") return payload;
  const pl = { ...(payload as Record<string, unknown>) };
  const prior = pl.verdicts && typeof pl.verdicts === "object" ? (pl.verdicts as Record<string, unknown>) : {};
  pl.verdicts = { ...prior, [step]: { decision, reason, output } };
  return pl;
}

export async function runPass(
  itemIn: Item,
  pipeline: Pipeline,
  gates: GateModule[],
  deps: RunnerDeps,
): Promise<RunPassResult> {
  const clock = deps.clock ?? defaultClock;
  const ordered = indexGates(pipeline, gates);
  let item: Item = {
    ...itemIn,
    history: [...itemIn.history],
  };
  const ran: string[] = [];

  let i = startIndex(ordered, item.step ?? ordered[0]!.id);
  for (; i < ordered.length; i++) {
    const gate = ordered[i]!;
    if (!gate.applies(item)) continue;
    item = {
      ...item,
      step: gate.id,
      state: "pending",
      parkedReason: undefined,
    };
    ran.push(gate.id);
    const verdict = await gate.run(item);
    const decision = gate.decide(verdict);
    // Persist the gate's full verdict (reasoning + structured output) into the
    // payload so the UI can surface WHY a gate passed/parked/failed — the
    // runner used to keep only the token string. Keyed by step.
    const payload = withVerdict(item.payload, gate.id, decision, verdict.verdict, verdict.output);
    if (decision === "pass") {
      item = {
        ...item,
        payload,
        state: "passed",
        parkedReason: undefined,
        history: [
          ...item.history,
          { step: gate.id, status: "passed", at: clock() },
        ],
      };
      continue;
    }
    const status = decision === "park" ? "parked" : "failed";
    const reason =
      typeof verdict.verdict === "string" ? verdict.verdict : decision;
    item = {
      ...item,
      payload,
      state: status,
      parkedReason: reason,
      history: [
        ...item.history,
        { step: gate.id, status, at: clock(), note: reason },
      ],
    };
    await deps.store.save(item);
    return { item, ran, stoppedBy: { step: gate.id, reason: status } };
  }
  await deps.store.save(item);
  return { item, ran };
}

export interface RewindOpts {
  clock?: Clock;
  // When given, rewind validates that toStep is one of the pipeline's gates
  // and throws UnknownStepError at the call site instead of deferring the
  // failure to the next runPass.
  pipeline?: Pipeline;
}

export function rewind(
  item: Item,
  toStep: string,
  note: string,
  opts: RewindOpts = {},
): Item {
  const clock = opts.clock ?? defaultClock;
  if (opts.pipeline && !opts.pipeline.gates.includes(toStep)) {
    throw new UnknownStepError(toStep);
  }
  return {
    ...item,
    step: toStep,
    state: "pending",
    parkedReason: undefined,
    history: [
      ...item.history,
      { step: toStep, status: "rewound", at: clock(), note },
    ],
  };
}
