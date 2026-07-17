import { z } from "zod";

// State — the execution state of an Item at its current step.
export const StateSchema = z.enum([
  "pending",
  "running", // the pipeline is executing this step now (set by the board's Run button)
  "passed",
  "parked",
  "failed",
]);
export type State = z.infer<typeof StateSchema>;

// Schedule — the "when" axis, orthogonal to the pipeline (the "what"). `now`
// runs on demand (board Run button / daytime); `nightly` defers an item to the
// unattended overnight lane. The executor is the same; only the trigger differs.
export const ScheduleSchema = z.enum(["now", "nightly"]);
export type Schedule = z.infer<typeof ScheduleSchema>;

export const HistoryEntrySchema = z.object({
  step: z.string().min(1), // the pipeline step this entry is about (gate id / "triage" / executor id)
  status: z.union([
    StateSchema,
    z.literal("rewound"),
    z.literal("entered"),
  ]),
  at: z.string().min(1),
  note: z.string().optional(),
});
export type HistoryEntry = z.infer<typeof HistoryEntrySchema>;

export const ItemSchema = z.object({
  id: z.string().min(1),
  pipeline: z.string().min(1), // identity link → Pipeline.pipeline (or UNTRIAGED for an idea)
  // `step` = position in the pipeline (a gate id, "triage", or an executor id);
  // present once triaged. `stage` = hopper maturation (captured/shaping/ready);
  // present while an idea is untriaged. Exactly one is meaningful at a time —
  // the split that retired the overloaded `phase` field.
  step: z.string().min(1).optional(),
  stage: z.string().min(1).optional(),
  state: StateSchema,
  parkedReason: z.string().optional(),
  payload: z.unknown(),
  history: z.array(HistoryEntrySchema),
  // Scheduling attributes — the "when", orthogonal to the pipeline. `schedule`
  // = now | nightly; `schedulePriority` orders the nightly queue (higher =
  // sooner). A project keeps its domain color; nightly is a skin on top.
  schedule: ScheduleSchema.optional(),
  schedulePriority: z.number().optional(),
  // chain: per-item auto-advance switch. When a pipeline declares `next`, an
  // item with chain=true auto-creates+kicks the successor on a clean pass (e.g.
  // project-ideation spec → build). Off (default) stops at this pipeline's
  // result for human review. Toggled on the board (POST /chain).
  chain: z.boolean().optional(),
  // archived: the exit ramp for engine items. A passed item that has aged out
  // (or whose chain is complete) leaves the working board and appears on
  // /finished instead — passed is a result, archived is the shelf. Set by the
  // board's archive sweep; cleared by any manual status move (revival).
  archived: z.boolean().optional(),
  archivedAt: z.string().optional(),
});
export type Item = z.infer<typeof ItemSchema>;

export const GateVerdictSchema = z.object({
  verdict: z.string().min(1),
  output: z.unknown(),
});
export type GateVerdict = z.infer<typeof GateVerdictSchema>;

export type GateDecision = "pass" | "park" | "fail";

export interface GateModule {
  readonly id: string;
  applies(item: Item): boolean;
  // CONTRACT: run() MUST be idempotent. On park-and-resume the runner re-enters
  // the parked phase and calls run() again, so a gate may execute more than once
  // for the same item. Gates that perform side effects must guard against repeats.
  run(item: Item): Promise<GateVerdict>;
  decide(verdict: GateVerdict): GateDecision;
}

// Item traits drive gate applicability (the data-driven half of the gate
// registry). They live on the item payload under `traits`; a profile may
// declare `defaultTraits` to stamp on every item it triages, so which gates
// fire is profile data rather than a hardcoded intake literal. `readTraits`
// (gates/traits.ts) reads them back off the payload at gate time.
export const ItemTraitsSchema = z.object({
  // greenfield = builds something new; brownfield = modifies what exists.
  mode: z.enum(["greenfield", "brownfield"]).optional(),
  // touches code the author didn't write (Chesterton's Fence territory).
  touchesExistingCode: z.boolean().optional(),
  // a trivial item (typo, rename) skips the heavier disciplines.
  trivial: z.boolean().optional(),
  // multi-part work that stepwise-refinement should decompose.
  multiPart: z.boolean().optional(),
  // write-mode execution (commits/pushes) vs read-only.
  writeMode: z.boolean().optional(),
});
export type ItemTraits = z.infer<typeof ItemTraitsSchema>;

// A Pipeline (formerly "profile"/"manifest") is the data-driven recipe for one
// kind of work — which gates fire, in what executor mode, with which executor
// and LLM. New kinds of work are new pipelines; the engine core never changes.
// Shape mirrors lead_scout's profile model (id/label/enabled/llmProvider + the
// gate list).
export const PipelineSchema = z.object({
  pipeline: z.string().min(1), // identity key; links item.pipeline → this pipeline
  label: z.string().min(1).optional(), // human-facing name for the board
  color: z.string().min(1).optional(), // hex tint for cards/legend (data-driven, lead_scout-style)
  source: z.string().min(1),
  gates: z.array(z.string().min(1)).min(1),
  // executorMode + executors are consumed by the executor (terminal step), not
  // the runner (which only walks `gates`).
  executorMode: z.string().min(1),
  executors: z.array(z.string().min(1)),
  // enabled gates whether triage may route to this pipeline (default true).
  enabled: z.boolean().optional(),
  // llmProvider selects the LlmPort adapter (claude-cli | anthropic-api |
  // ollama); default "claude-cli". Late-bound by the adapter resolver.
  llmProvider: z.string().min(1).optional(),
  // autoRun: when an item enters this pipeline (via triage/intake), run it
  // immediately instead of waiting for the board's Run button. Manual pipelines
  // (project-ideation) leave this false so a human triggers each run;
  // event-driven pipelines (incoming SR tickets) set it true. Default false.
  autoRun: z.boolean().optional(),
  // next: the pipeline an item auto-advances into after a clean pass (the
  // declarative chain link). project-ideation → build: a developed spec hands
  // off to the builder. Per-item gated by item.chain; absent = terminal.
  next: z.string().min(1).optional(),
  // defaultTraits stamped on every item this pipeline triages. Greenfield
  // pipelines omit it (intake's greenfield default applies); brownfield
  // pipelines (app-refinement) declare {mode:"brownfield",touchesExistingCode:true,…}
  // so the fixing-systems gates (chestertons-fence, principles-fix, blast-radius)
  // actually fire. Data-driven: applicability is pipeline data, not intake code.
  defaultTraits: ItemTraitsSchema.optional(),
});
export type Pipeline = z.infer<typeof PipelineSchema>;

export interface ItemStore {
  load(id: string): Promise<Item | null>;
  save(item: Item): Promise<void>;
  list(): Promise<Item[]>;
  delete(id: string): Promise<void>;
}

// An Executor performs the side-effecting terminal step of a pipeline (after a
// clean gate pass). Like gates, the core knows only this port; concrete
// executors (native = worktree+headless-claude, gauntlet = dispatch to an
// external standalone gauntlet, spec = synthesize+write a spec) are constructed
// with their own injected adapters.
export type ExecutorOutcome = "succeeded" | "failed";

export interface ExecutorResult {
  outcome: ExecutorOutcome;
  verdict: string | null; // the parsed self-verdict token, if any
  reportPresent: boolean; // did the agent write the required report
  branch: string | null; // branch pushed (write mode) or null
  pristine: boolean | null; // worktree clean check (read-only) or null in write mode
  pushed: boolean;
  detail: string; // human-readable outcome summary
  output: unknown; // structured detail for downstream steps
}

export interface Executor {
  readonly id: string;
  run(item: Item): Promise<ExecutorResult>;
}
