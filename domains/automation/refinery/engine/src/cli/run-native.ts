// Privileged native runner — the engine half of the "spool → privileged native
// runner" split. The hardened board no longer runs the `native` executor itself
// (no repo, no git push keys, no worktree perms): it runs the gates in-process
// and SPOOLS an execute request. A separate, privileged systemd unit drains the
// spool by invoking the `refinery-run-native` bin, which is THIS file.
//
// `runNative({id}, deps)` is the injectable core (store, catalog, buildExecutor,
// clock) so tests drive it with an in-memory store + stub executor; `main()`
// late-binds config from env and wires the real adapters. It loads the item,
// resolves its pipeline, builds + runs the native executor, and FINALIZES the
// item exactly like run-once.ts does after integrate (executorResult on the
// payload, state passed/failed, a history entry).

import { Clock } from "../runner.js";
import { Executor, Item, ItemStore, Pipeline } from "../contracts.js";

/** Minimal pipeline lookup port — the catalog narrowed to what runNative needs. */
export interface PipelineLookup {
  get(pipeline: string): Pipeline | null;
}

export interface RunNativeDeps {
  store: ItemStore;
  catalog: PipelineLookup;
  /** Build the native executor for a resolved pipeline + item (injected so tests
   *  stub the executor / ports; prod wires buildNativeExecutor + real ports). */
  buildExecutor(pipeline: Pipeline, item: Item): Executor;
  clock?: Clock;
}

/** Load the item, build + run its native executor, and finalize the item the
 *  same way runPipelineOnce finalizes after integrate. Returns the done item. */
export async function runNative(
  opts: { id: string },
  deps: RunNativeDeps,
): Promise<Item> {
  const item = await deps.store.load(opts.id);
  if (!item) throw new Error(`run-native: no such item "${opts.id}"`);
  const pipeline = deps.catalog.get(item.pipeline);
  if (!pipeline) throw new Error(`run-native: unknown pipeline "${item.pipeline}" for item "${opts.id}"`);

  const at = (deps.clock ?? (() => new Date().toISOString()))();
  const basePayload =
    item.payload && typeof item.payload === "object"
      ? (item.payload as Record<string, unknown>)
      : {};

  // Building or running the native executor can throw (no target repo, git/claude
  // failure). The board already marked this item "running" and spooled it, so on
  // ANY failure we must finalize it as failed — otherwise it is stuck running.
  try {
    const executor = deps.buildExecutor(pipeline, item);
    const result = await executor.run(item);
    const status = result.outcome === "succeeded" ? "passed" : "failed";
    const done: Item = {
      ...item,
      payload: { ...basePayload, executorResult: result },
      state: status,
      history: [...item.history, { step: executor.id, status, at, note: result.detail }],
    };
    await deps.store.save(done);
    return done;
  } catch (e) {
    const msg = (e as Error).message;
    const done: Item = {
      ...item,
      state: "failed",
      parkedReason: `native run error: ${msg}`,
      history: [...item.history, { step: item.step ?? "native", status: "failed", at, note: `native run error: ${msg}` }],
    };
    await deps.store.save(done);
    return done;
  }
}

// ── CLI shell ───────────────────────────────────────────────────────────────

function parseId(argv: string[]): string {
  const i = argv.indexOf("--id");
  if (i >= 0 && argv[i + 1] !== undefined) return argv[i + 1]!;
  throw new Error("missing required --id");
}

async function main(): Promise<void> {
  const { MarkdownItemStore } = await import("../stores/markdown-store.js");
  const { PipelineCatalog } = await import("../pipelines/catalog.js");
  const { makeGitWorktree } = await import("../adapters/git-worktree.js");
  const { makeClaudeHeadless } = await import("../adapters/claude-headless.js");
  const { makeReportFs } = await import("../adapters/report-fs.js");
  const { buildNativeExecutor } = await import("../executors/native-factory.js");

  const id = parseId(process.argv.slice(2));
  const home = process.env.HOME ?? "/tmp";
  const base = `${home}/.local/state/refinery`;
  const itemsDir = process.env.REFINERY_ITEMS_DIR || `${base}/items`;
  const pipelinesDir = process.env.REFINERY_PIPELINES_DIR || "pipelines";
  const pipelineStatePath = process.env.REFINERY_PIPELINE_STATE || `${base}/profiles.json`;
  const scratchDir = process.env.REFINERY_SCRATCH_DIR || `${base}/specs`;
  const nativeRepo = process.env.REFINERY_NATIVE_REPO;
  const nativeTimeoutMs = process.env.REFINERY_NATIVE_TIMEOUT
    ? Number(process.env.REFINERY_NATIVE_TIMEOUT)
    : undefined;
  const claudeBin = process.env.REFINERY_CLAUDE_BIN;

  const store = new MarkdownItemStore(itemsDir);
  const catalog = new PipelineCatalog({ dir: pipelinesDir, statePath: pipelineStatePath });
  const ports = {
    git: makeGitWorktree(),
    claude: makeClaudeHeadless(claudeBin ? { bin: claudeBin } : {}),
    report: makeReportFs(),
  };

  const done = await runNative(
    { id },
    {
      store,
      catalog,
      buildExecutor: (pipeline, item) =>
        buildNativeExecutor(
          pipeline,
          item,
          { nativeRepo, scratchDir, pipelinesDir, nativeTimeoutMs, clock: () => new Date().toISOString() },
          ports,
        ),
      clock: () => new Date().toISOString(),
    },
  );

  const r = done.payload as { executorResult?: { detail?: string } };
  process.stderr.write(`run-native: ${id} → ${done.state} (${r.executorResult?.detail ?? "no detail"})\n`);
}

// Run only when invoked as the bin entry (not when imported by tests).
const invokedDirectly =
  process.argv[1] !== undefined && /run-native(\.[cm]?js|\.ts)?$/.test(process.argv[1]);
if (invokedDirectly) {
  main().catch((e) => {
    process.stderr.write(`refinery run-native: ${(e as Error).message}\n`);
    process.exitCode = 1;
  });
}
