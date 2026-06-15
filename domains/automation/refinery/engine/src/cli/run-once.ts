// Orchestration core for "run a genre one pass" — the testable heart of the
// CLI shell. Loads-or-creates the item, runs it through the profile's gate
// pipeline (slice-03 runner + slice-04 gates), and — only if every gate passed
// — fires the genre's integrate effector. Everything is injected (profile,
// gates, integrate effector, store, clock) so the e2e test drives it with a
// stub LLM and tmp dirs; cli.ts wires the real adapters.

import { Clock, runPass } from "../runner.js";
import {
  EffectorResult,
  GateModule,
  Item,
  ItemEffector,
  ItemStore,
  Profile,
} from "../contracts.js";

export interface GenreDeps {
  profile: Profile;
  gates: GateModule[];
  integrate: ItemEffector;
  store: ItemStore;
  clock?: Clock;
}

export interface RunOnceResult {
  item: Item;
  ran: string[];
  parked: boolean;
  integrated: EffectorResult | null;
}

/** Build a fresh item for a project-ideation-style genre from an input sentence. */
export function newIdeationItem(
  id: string,
  genre: string,
  input: string,
  firstStage: string,
): Item {
  return {
    id,
    genre,
    stage: firstStage,
    stageStatus: "pending",
    payload: {
      input,
      title: input.length > 80 ? `${input.slice(0, 77)}…` : input,
      // project ideation builds something new and is non-trivial / multi-part.
      traits: { mode: "greenfield", trivial: false, multiPart: true },
    },
    history: [],
  };
}

export async function runGenreOnce(
  opts: { id: string; input: string },
  deps: GenreDeps,
): Promise<RunOnceResult> {
  const existing = await deps.store.load(opts.id);
  const item =
    existing ??
    newIdeationItem(opts.id, deps.profile.genre, opts.input, deps.profile.gates[0]!);

  const result = await runPass(item, deps.profile, deps.gates, {
    store: deps.store,
    clock: deps.clock,
  });

  // Parked or failed at a gate → stop; integrate only runs on a clean pass.
  if (result.stoppedBy) {
    return { item: result.item, ran: result.ran, parked: true, integrated: null };
  }

  const integrated = await deps.integrate.run(result.item);
  const at = (deps.clock ?? (() => new Date().toISOString()))();
  const done: Item = {
    ...result.item,
    history: [
      ...result.item.history,
      {
        stage: deps.integrate.id,
        status: integrated.outcome === "succeeded" ? "passed" : "failed",
        at,
        note: integrated.detail,
      },
    ],
  };
  await deps.store.save(done);
  return { item: done, ran: result.ran, parked: false, integrated };
}
