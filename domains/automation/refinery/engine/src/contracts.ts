import { z } from "zod";

export const StageStatusSchema = z.enum([
  "pending",
  "passed",
  "parked",
  "failed",
]);
export type StageStatus = z.infer<typeof StageStatusSchema>;

export const HistoryEntrySchema = z.object({
  stage: z.string().min(1),
  status: z.union([
    StageStatusSchema,
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
  stage: z.string().min(1),
  stageStatus: StageStatusSchema,
  parkedReason: z.string().optional(),
  payload: z.unknown(),
  history: z.array(HistoryEntrySchema),
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
  run(item: Item): Promise<GateVerdict>;
  decide(verdict: GateVerdict): GateDecision;
}

export const ManifestSchema = z.object({
  genre: z.string().min(1),
  source: z.string().min(1),
  gates: z.array(z.string().min(1)).min(1),
  executeMode: z.string().min(1),
  effectors: z.array(z.string().min(1)),
});
export type Manifest = z.infer<typeof ManifestSchema>;

export interface ItemStore {
  load(id: string): Promise<Item | null>;
  save(item: Item): Promise<void>;
  list(): Promise<Item[]>;
}
