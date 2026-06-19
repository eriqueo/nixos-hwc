// Per-pipeline native-executor config — the runtime knobs that aren't on the
// Pipeline schema (verdict token, which verdicts count as success, report file,
// branch prefix). The Pipeline carries executorMode + the gate list; this
// carries the native executor's knobs. `nightly-build`/`datax-sr` reproduce the
// two external gauntlets (the "two gauntlets are one machine" proof); they stay
// external-owned at runtime (the board refuses to native-run them). `app-refinement`
// is the first board-owned native pipeline.

export interface GauntletExecuteConfig {
  executorMode: "write" | "read-only";
  verdictPattern: RegExp;
  successVerdicts: string[];
  reportFile: string;
  branchPrefix?: string; // write mode only
}

export const GAUNTLET_CONFIGS: Record<string, GauntletExecuteConfig> = {
  "nightly-build": {
    executorMode: "write",
    verdictPattern: /NIGHTLY-VERDICT: (success|failure)/,
    successVerdicts: ["success"],
    reportFile: "REPORT.md",
    branchPrefix: "nightly/",
  },
  "datax-sr": {
    executorMode: "read-only",
    verdictPattern: /SR-VERDICT: (investigated|inconclusive)/,
    successVerdicts: ["investigated", "inconclusive"],
    reportFile: "REPORT.md",
  },
  "app-refinement": {
    executorMode: "write",
    verdictPattern: /APP-REFINEMENT-VERDICT: (success|blocked|failure)/,
    successVerdicts: ["success"],
    reportFile: "REPORT.md",
    branchPrefix: "app-refinement/",
  },
};
