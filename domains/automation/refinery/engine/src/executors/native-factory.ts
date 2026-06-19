// Shared native-executor factory. Builds a fully-configured native Executor for
// one pipeline + item, encapsulating the per-pipeline config lookup
// (GAUNTLET_CONFIGS), the repo/branch/worktree/prompt resolution, and the
// timeout default. Used by BOTH the privileged native runner CLI (run-native.ts)
// and — historically — the board; the board now spools instead of building this
// in-process, but the resolution logic lives here so there is one source of truth.
//
// Hexagonal: ports (git/claude/report) are injected; this file is pure config
// assembly + a call to makeNativeExecutor. No IO of its own beyond an existsSync
// for the optional prompt wrapper.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Item, Executor, Pipeline } from "../contracts.js";
import { makeNativeExecutor, NativePorts } from "./native.js";
import { GAUNTLET_CONFIGS } from "../pipelines/gauntlet-config.js";

// Fallback native-executor wrapper when a pipeline ships no prompt file. The
// item (its payload) is appended after this by the executor; the agent must
// write the report file and end with the pipeline's verdict token.
export const DEFAULT_NATIVE_WRAPPER = [
  "You are executing a refinery pipeline item in a disposable git worktree.",
  "Do the work described under THE ITEM. Make the smallest correct change; do not",
  "bundle unrelated edits. When done, write REPORT.md (what you did, why, how it",
  "was verified) to the worktree root, and end your output with the verdict token",
  "your pipeline expects on its own line.",
].join("\n");

/** Slug a string into a branch-safe fragment (≤40 chars). */
export function slug(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "item";
}

export interface BuildNativeOpts {
  nativeRepo?: string; // default target repo when payload.repo is absent
  scratchDir: string; // worktrees live under <scratchDir>/wt/<id>
  pipelinesDir: string; // prompts/<pipeline>.md is looked up here
  defaultWrapper?: string; // override the built-in DEFAULT_NATIVE_WRAPPER
  nativeTimeoutMs?: number; // headless-claude timeout (default 3h)
  clock: () => string; // for the write-mode branch date
}

/** Build a native Executor for `pipeline` + `item`. Throws (fail-loud) when the
 *  pipeline has no native config or no target repo can be resolved. */
export function buildNativeExecutor(
  pipeline: Pipeline,
  item: Item,
  opts: BuildNativeOpts,
  ports: NativePorts,
): Executor {
  const ncfg = GAUNTLET_CONFIGS[pipeline.pipeline];
  if (!ncfg) throw new Error(`native executor has no config for pipeline "${pipeline.pipeline}"`);

  const pl = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
  const repo = (typeof pl.repo === "string" && pl.repo) || opts.nativeRepo;
  if (!repo) {
    throw new Error(
      `native pipeline "${pipeline.pipeline}" needs a target repo — set payload.repo on the item or REFINERY_NATIVE_REPO`,
    );
  }

  const date = opts.clock().slice(0, 10);
  const branch =
    ncfg.executorMode === "write"
      ? `${ncfg.branchPrefix ?? `${pipeline.pipeline}/`}${date}-${slug(item.id)}`
      : undefined;

  const promptFile = join(opts.pipelinesDir, "prompts", `${pipeline.pipeline}.md`);
  const promptWrapper = existsSync(promptFile)
    ? readFileSync(promptFile, "utf8")
    : opts.defaultWrapper ?? DEFAULT_NATIVE_WRAPPER;

  return makeNativeExecutor(
    {
      repo,
      worktree: join(opts.scratchDir, "wt", item.id),
      executorMode: ncfg.executorMode,
      branch,
      promptWrapper,
      verdictPattern: ncfg.verdictPattern,
      successVerdicts: ncfg.successVerdicts,
      timeoutMs: opts.nativeTimeoutMs ?? 3 * 60 * 60 * 1000,
      reportFile: ncfg.reportFile,
    },
    ports,
  );
}
