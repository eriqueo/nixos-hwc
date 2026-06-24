// Orchestration core for "run a pipeline one pass" — the testable heart of the
// CLI shell. Loads-or-creates the item, runs it through the pipeline's gate
// pipeline (slice-03 runner + slice-04 gates), and — only if every gate passed
// — fires the pipeline's integrate executor. Everything is injected (pipeline,
// gates, integrate executor, store, clock) so the e2e test drives it with a
// stub LLM and tmp dirs; cli.ts wires the real adapters.

import { Clock, runPass } from "../runner.js";
import {
  ExecutorResult,
  GateModule,
  Item,
  Executor,
  ItemStore,
  Pipeline,
} from "../contracts.js";

export interface PipelineDeps {
  pipeline: Pipeline;
  gates: GateModule[];
  integrate: Executor;
  store: ItemStore;
  clock?: Clock;
}

export interface RunOnceResult {
  item: Item;
  ran: string[];
  parked: boolean;
  integrated: ExecutorResult | null;
}

/** Build a fresh item for a project-ideation-style pipeline from an input sentence. */
export function newIdeationItem(
  id: string,
  pipeline: string,
  input: string,
  firstStep: string,
): Item {
  return {
    id,
    pipeline,
    step: firstStep,
    state: "pending",
    payload: {
      input,
      title: input.length > 80 ? `${input.slice(0, 77)}…` : input,
      // project ideation builds something new and is non-trivial / multi-part.
      traits: { mode: "greenfield", trivial: false, multiPart: true },
    },
    history: [],
  };
}

export async function runPipelineOnce(
  opts: { id: string; input: string },
  deps: PipelineDeps,
): Promise<RunOnceResult> {
  const existing = await deps.store.load(opts.id);
  const item =
    existing ??
    newIdeationItem(opts.id, deps.pipeline.pipeline, opts.input, deps.pipeline.gates[0]!);

  const result = await runPass(item, deps.pipeline, deps.gates, {
    store: deps.store,
    clock: deps.clock,
  });

  // Parked or failed at a gate → stop; integrate only runs on a clean pass.
  if (result.stoppedBy) {
    return { item: result.item, ran: result.ran, parked: true, integrated: null };
  }

  const integrated = await deps.integrate.run(result.item);
  const at = (deps.clock ?? (() => new Date().toISOString()))();
  // Persist the full executor result (branch/pushed/pristine/verdict/detail)
  // into the payload so the UI can surface what the executor did — history kept
  // only the one-line detail before.
  const basePayload =
    result.item.payload && typeof result.item.payload === "object"
      ? (result.item.payload as Record<string, unknown>)
      : {};
  const done: Item = {
    ...result.item,
    payload: { ...basePayload, executorResult: integrated },
    state: integrated.outcome === "succeeded" ? "passed" : "failed",
    history: [
      ...result.item.history,
      {
        step: deps.integrate.id,
        status: integrated.outcome === "succeeded" ? "passed" : "failed",
        at,
        note: integrated.detail,
      },
    ],
  };
  await deps.store.save(done);
  return { item: done, ran: result.ran, parked: false, integrated };
}
