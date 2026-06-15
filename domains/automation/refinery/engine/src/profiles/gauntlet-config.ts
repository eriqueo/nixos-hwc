// Per-gauntlet execute-effector config — the bits that aren't on the Profile
// schema (verdict token, which verdicts count as success, report file, branch
// prefix). The Profile carries executeMode + the gate pipeline; this carries
// the execute effector's runtime knobs. Together they let one engine reproduce
// both gauntlets (the slice-09 "two gauntlets are one machine" proof).

export interface GauntletExecuteConfig {
  executeMode: "write" | "read-only";
  verdictPattern: RegExp;
  successVerdicts: string[];
  reportFile: string;
  branchPrefix?: string; // write mode only
}

export const GAUNTLET_CONFIGS: Record<string, GauntletExecuteConfig> = {
  "nightly-build": {
    executeMode: "write",
    verdictPattern: /NIGHTLY-VERDICT: (success|failure)/,
    successVerdicts: ["success"],
    reportFile: "REPORT.md",
    branchPrefix: "nightly/",
  },
  "datax-sr": {
    executeMode: "read-only",
    verdictPattern: /SR-VERDICT: (investigated|inconclusive)/,
    successVerdicts: ["investigated", "inconclusive"],
    reportFile: "REPORT.md",
  },
};
