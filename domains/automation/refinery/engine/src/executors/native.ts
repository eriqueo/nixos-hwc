// The native executor — one mode-parameterized implementation of the
// worktree → headless-claude → verdict-parse → report-check → push/pristine
// logic that was duplicated across nightly-builds/run.sh (write mode) and
// sr_gauntlet/run.sh (read-only mode). The two differ only on:
//   - executorMode: write (commit+push) vs read-only (assert pristine)
//   - verdict token: e.g. NIGHTLY-VERDICT vs SR-VERDICT
//   - which verdict values count as a successful run
// so all three are config here. git + claude + the report check are injected
// ports (./ports.ts) — this file is pure control flow.
//
// Scope note: this is a PARALLEL extraction. The live run.sh files are NOT
// touched by this card; adopting the executor is slice 09.

import { Item, Executor, ExecutorResult } from "../contracts.js";
import { ClaudePort, GitPort, ReportPort } from "./ports.js";

export type NativeMode = "write" | "read-only";

export interface NativeConfig {
  id?: string; // executor id (default "native")
  repo: string;
  worktree: string; // disposable worktree path the caller assigns
  executorMode: NativeMode;
  branch?: string; // required for write mode; ignored for read-only (detached)
  promptWrapper: string; // wrapper text; the item payload is appended after a rule
  verdictPattern: RegExp; // must capture the verdict token in group 1
  successVerdicts: string[]; // verdict values that count as a successful run
  timeoutMs: number;
  reportFile: string; // e.g. "REPORT.md"
  keepWorktree?: boolean; // default false — remove the worktree when done
}

export interface NativePorts {
  git: GitPort;
  claude: ClaudePort;
  report: ReportPort;
}

/** Compose the agent prompt: wrapper, then the item payload after a separator. */
export function composeNativePrompt(wrapper: string, item: Item): string {
  const payloadText =
    typeof item.payload === "string"
      ? item.payload
      : JSON.stringify(item.payload, null, 2);
  return `${wrapper}\n\n---\n\n# THE ITEM\n\n${payloadText}`;
}

/** Parse the last verdict token matched by the pattern, or null. */
export function parseNativeVerdict(stdout: string, pattern: RegExp): string | null {
  const flags = pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g";
  const re = new RegExp(pattern.source, flags);
  let last: string | null = null;
  for (const m of stdout.matchAll(re)) {
    if (m[1] !== undefined) last = m[1];
  }
  return last;
}

export function makeNativeExecutor(
  cfg: NativeConfig,
  ports: NativePorts,
): Executor {
  if (cfg.executorMode === "write" && !cfg.branch) {
    throw new Error("native executor: write mode requires cfg.branch");
  }
  const id = cfg.id ?? "native";

  const fail = (detail: string, partial: Partial<ExecutorResult> = {}): ExecutorResult => ({
    outcome: "failed",
    verdict: null,
    reportPresent: false,
    branch: cfg.executorMode === "write" ? cfg.branch ?? null : null,
    pristine: null,
    pushed: false,
    detail,
    output: {},
    ...partial,
  });

  return {
    id,
    async run(item: Item): Promise<ExecutorResult> {
      const base = await ports.git.resolveBase(cfg.repo);

      let worktreeAdded = false;
      try {
        try {
          await ports.git.addWorktree({
            repo: cfg.repo,
            worktree: cfg.worktree,
            base,
            branch: cfg.executorMode === "write" ? cfg.branch : undefined,
          });
          worktreeAdded = true;
        } catch (e) {
          return fail(`worktree add failed: ${(e as Error).message}`);
        }

        const prompt = composeNativePrompt(cfg.promptWrapper, item);
        const res = await ports.claude.run({
          prompt,
          cwd: cfg.worktree,
          timeoutMs: cfg.timeoutMs,
          readOnly: cfg.executorMode === "read-only",
        });

        const verdict = parseNativeVerdict(res.stdout, cfg.verdictPattern);
        const reportPresent = await ports.report.exists({
          worktree: cfg.worktree,
          reportFile: cfg.reportFile,
        });

        let pushed = false;
        let pristine: boolean | null = null;

        if (cfg.executorMode === "write") {
          // Push whatever was committed — a failed run's partial branch is still
          // reviewable (gate 8). Only push if there are commits beyond base.
          if (!res.timedOut && (await ports.git.hasCommitsBeyond({ worktree: cfg.worktree, base }))) {
            await ports.git.push({ worktree: cfg.worktree, branch: cfg.branch! });
            pushed = true;
          }
        } else {
          // Read-only invariant: the worktree must have stayed pristine; revert if not.
          pristine = await ports.git.isPristine(cfg.worktree);
          if (!pristine) await ports.git.revert(cfg.worktree);
        }

        const verdictOk = verdict !== null && cfg.successVerdicts.includes(verdict);
        const modeOk = cfg.executorMode === "write" ? true : pristine === true;
        const succeeded =
          res.exitCode === 0 && !res.timedOut && reportPresent && verdictOk && modeOk;

        const detail = succeeded
          ? `${cfg.executorMode} run succeeded (verdict=${verdict})`
          : `run failed: exit=${res.exitCode} timedOut=${res.timedOut} verdict=${verdict ?? "none"} report=${reportPresent ? "yes" : "no"}${cfg.executorMode === "read-only" ? ` pristine=${pristine}` : ""}`;

        return {
          outcome: succeeded ? "succeeded" : "failed",
          verdict,
          reportPresent,
          branch: cfg.executorMode === "write" ? cfg.branch ?? null : null,
          pristine,
          pushed,
          detail,
          output: { exitCode: res.exitCode, timedOut: res.timedOut, base },
        };
      } finally {
        if (worktreeAdded && !cfg.keepWorktree) {
          await ports.git
            .removeWorktree({ repo: cfg.repo, worktree: cfg.worktree })
            .catch(() => {});
        }
      }
    },
  };
}
