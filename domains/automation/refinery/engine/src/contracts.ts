import { z } from "zod";

export const PhaseStatusSchema = z.enum([
  "pending",
  "passed",
  "parked",
  "failed",
]);
export type PhaseStatus = z.infer<typeof PhaseStatusSchema>;

export const HistoryEntrySchema = z.object({
  phase: z.string().min(1),
  status: z.union([
    PhaseStatusSchema,
    z.literal("rewound"),
    z.literal("entered"),
  ]),
  at: z.string().min(1),
  note: z.string().optional(),
});
export type HistoryEntry = z.infer<typeof HistoryEntrySchema>;

export const ItemSchema = z.object({
  id: z.string().min(1),
  genre: z.string().min(1),
  phase: z.string().min(1),
  phaseStatus: PhaseStatusSchema,
  parkedReason: z.string().optional(),
  payload: z.unknown(),
  history: z.array(HistoryEntrySchema),
  // Scheduling attributes — orthogonal to the profile (the "when", not the
  // "what"). `nightly` flags a project for the overnight gauntlet run;
  // `nightlyPriority` orders the nightly queue (higher = sooner). A project
  // keeps its profile color; nightly is a skin on top.
  nightly: z.boolean().optional(),
  nightlyPriority: z.number().optional(),
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

// A Profile (formerly "manifest") is the data-driven recipe for one genre of
// work — which gates fire, in what execute mode, with which effectors and LLM.
// New genres are new profiles; the engine core never changes. Shape mirrors
// lead_scout's profile model (id/label/enabled/llmProvider + the pipeline).
export const ProfileSchema = z.object({
  genre: z.string().min(1), // identity key; links item.genre → profile
  label: z.string().min(1).optional(), // human-facing name for the board
  color: z.string().min(1).optional(), // hex tint for cards/legend (data-driven, lead_scout-style)
  source: z.string().min(1),
  gates: z.array(z.string().min(1)).min(1),
  // executeMode + effectors are consumed by the execute/integrate effectors,
  // not the phase runner (which only walks `gates`).
  executeMode: z.string().min(1),
  effectors: z.array(z.string().min(1)),
  // enabled gates whether triage may route to this profile (default true).
  enabled: z.boolean().optional(),
  // llmProvider selects the LlmPort adapter (claude-cli | anthropic-api |
  // ollama); default "claude-cli". Late-bound by the adapter resolver.
  llmProvider: z.string().min(1).optional(),
});
export type Profile = z.infer<typeof ProfileSchema>;

export interface ItemStore {
  load(id: string): Promise<Item | null>;
  save(item: Item): Promise<void>;
  list(): Promise<Item[]>;
  delete(id: string): Promise<void>;
}

// An effector performs the side-effecting phases of the pipeline (execute,
// integrate, notify). Like gates, the core knows only this port; concrete
// effectors (worktree+headless-claude execute, PR/brain-fold integrate, …) are
// constructed with their own injected adapters.
export type EffectorOutcome = "succeeded" | "failed";

export interface EffectorResult {
  outcome: EffectorOutcome;
  verdict: string | null; // the parsed self-verdict token, if any
  reportPresent: boolean; // did the agent write the required report
  branch: string | null; // branch pushed (write mode) or null
  pristine: boolean | null; // worktree clean check (read-only) or null in write mode
  pushed: boolean;
  detail: string; // human-readable outcome summary
  output: unknown; // structured detail for downstream phases
}

export interface ItemEffector {
  readonly id: string;
  run(item: Item): Promise<EffectorResult>;
}
