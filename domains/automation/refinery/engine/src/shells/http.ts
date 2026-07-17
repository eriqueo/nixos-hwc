// HTTP shell over the engine core (hexagonal: a shell translating inbound HTTP
// into core calls). Serves the Flow / Hopper / Overnight / Finished / SR /
// Reviews / Reference pages, a per-item pipeline detail page, and the
// intake/amend/rewind/promote/schedule endpoints, operating on the
// MarkdownItemStore + PipelineCatalog + triage. All config late-bound from env.

import { createServer, IncomingMessage, ServerResponse } from "node:http";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { Item } from "../contracts.js";
import { MarkdownItemStore } from "../stores/markdown-store.js";
import { PipelineCatalog } from "../pipelines/catalog.js";
import { loadDomains, domainOf } from "../domains.js";
import { resolveLlm } from "../adapters/resolver.js";
import { triageSentence, makeTriagedItem, UNTRIAGED } from "../triage.js";
import { rewind, runPass } from "../runner.js";
import { gateList } from "../gates/index.js";
import { makeSpecExecutor } from "../executors/spec.js";
import { runPipelineOnce } from "../cli/run-once.js";
import { LlmPort } from "../gates/llm-port.js";
import { nightlyCardProjects, queueNextStep, unqueueStep, parseNbId, readReport, hasActiveStep, readProjectMode, setProjectMode, NB_PREFIX, finishedProjects, reopenProject, parseFinishedId, FINISHED_PREFIX } from "../sources/nightly-cards.js";
import { srInvestigationProjects, readRunFile, SR_PREFIX } from "../sources/sr-investigations.js";
import { syncBrainIdeas, makeIdeaItem, ideaId, isBrainIdea, appendBrainIdea, removeBrainIdea, promoteBrainIdea } from "../sources/brain-ideas.js";
import { renderBoard, renderNightly, renderNightlyProject, renderFinished, renderFinishedProject, renderSr, renderSrDetail, renderProjectDetail, renderReport, renderReference, renderReviews, HOPPER_STAGE_KEYS } from "./render.js";
import { FileReviewsStore, resolveReviewsDir } from "../stores/reviews-store.js";

export interface HttpShellConfig {
  port: number;
  itemsDir: string;
  pipelinesDir: string;
  domainsFile?: string; // domains registry (color + tag identity axis); optional
  pipelineStatePath: string;
  capsPath: string; // per-gauntlet "max per run" caps, written by the GUI
  scratchDir: string; // where the spec executor drops developed specs
  triageProvider: string;
  vaultDir?: string; // brain vault — nightly-builds card mirror + queue write-back
  srGauntletDir?: string; // sr_gauntlet dir — SR investigation mirror
  reviewsDir?: string; // morning PR-review records (REFINERY_REVIEWS_DIR); default under the state base
  runNowSpoolDir: string; // "Run now" / IMMEDIATE drops a <goal> request file here; a systemd.path twin of run.sh drains it
  srRunNowSpoolDir: string; // SR "re-investigate now" drops an <srId> request file here; sr-gauntlet-runnow.path drains it
  nativeRunNowSpoolDir: string; // board-owned native pipelines (app-refinement): after a clean gate pass the board drops an <itemId> file here; refinery-run-native.path drains it
  clock: () => string;
  triageLlm?: LlmPort; // test override; production resolves from triageProvider
  runLlm?: LlmPort; // test override for the pipeline runner; prod resolves per pipeline
  nativeRepo?: string; // default target repo for native pipelines (REFINERY_NATIVE_REPO); payload.repo overrides
  nativeTimeoutMs?: number; // headless-claude timeout for a native run (REFINERY_NATIVE_TIMEOUT)
  archiveAfterDays?: number; // passed items older than this leave the board for /finished (REFINERY_ARCHIVE_DAYS; default 7)
}

export function configFromEnv(): HttpShellConfig {
  const home = process.env.HOME ?? "/tmp";
  const base = `${home}/.local/state/refinery`;
  return {
    port: Number(process.env.REFINERY_PORT || 8060),
    itemsDir: process.env.REFINERY_ITEMS_DIR || `${base}/items`,
    pipelinesDir: process.env.REFINERY_PIPELINES_DIR || "pipelines",
    domainsFile: process.env.REFINERY_DOMAINS_FILE,
    pipelineStatePath: process.env.REFINERY_PIPELINE_STATE || `${base}/profiles.json`,
    capsPath: process.env.REFINERY_CAPS_FILE || `${base}/caps.json`,
    scratchDir: process.env.REFINERY_SCRATCH_DIR || `${base}/specs`,
    triageProvider: process.env.REFINERY_TRIAGE_PROVIDER || "claude-cli",
    vaultDir: process.env.REFINERY_VAULT_DIR,
    srGauntletDir: process.env.REFINERY_SR_GAUNTLET_DIR,
    reviewsDir: process.env.REFINERY_REVIEWS_DIR || `${base}/reviews`,
    runNowSpoolDir: process.env.REFINERY_RUNNOW_SPOOL || `${base}/run-now`,
    srRunNowSpoolDir: process.env.REFINERY_SR_RUNNOW_SPOOL || `${base}/sr-run-now`,
    nativeRunNowSpoolDir: process.env.REFINERY_NATIVE_RUNNOW_SPOOL || `${base}/native-run`,
    nativeRepo: process.env.REFINERY_NATIVE_REPO,
    nativeTimeoutMs: process.env.REFINERY_NATIVE_TIMEOUT ? Number(process.env.REFINERY_NATIVE_TIMEOUT) : undefined,
    archiveAfterDays: process.env.REFINERY_ARCHIVE_DAYS ? Number(process.env.REFINERY_ARCHIVE_DAYS) : undefined,
    clock: () => new Date().toISOString(),
  };
}

// Pipelines owned by an external standalone gauntlet (their run.sh timers + spools
// remain the executor). The board surfaces them read-only and triggers them via
// the run-now spool — it must never native-run them (double-execution guard).
const EXTERNAL_GAUNTLET_PIPELINES = new Set(["nightly-build", "datax-sr"]);

function readBody(req: IncomingMessage): Promise<URLSearchParams> {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > 1_000_000) reject(new Error("body too large"));
    });
    req.on("end", () => resolve(new URLSearchParams(data)));
    req.on("error", reject);
  });
}

function slug(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "item";
}

function redirectTo(res: ServerResponse, location: string): void {
  res.writeHead(303, { location });
  res.end();
}

export function createShell(cfg: HttpShellConfig) {
  const store = new MarkdownItemStore(cfg.itemsDir);
  const catalog = new PipelineCatalog({ dir: cfg.pipelinesDir, statePath: cfg.pipelineStatePath });
  const domains = loadDomains(cfg.domainsFile);

  // Morning PR reviews are read-only here (the morning-review CLI writes them).
  // Listing is lazy + dir-guarded so the page renders an empty state when the
  // reviews dir doesn't exist yet (don't create it on a GET).
  const reviewsDir = resolveReviewsDir(cfg.reviewsDir);
  const listReviews = async () => (existsSync(reviewsDir) ? new FileReviewsStore(reviewsDir).list() : []);

  // Per-gauntlet "max per run" caps — the single runtime source of truth that
  // both run.sh files read (with their env value as fallback). Refinery is the
  // control plane; the GUI writes these.
  type CapKind = "nightly" | "sr";
  const CAP_DEFAULTS: Record<CapKind, number> = { nightly: 1, sr: 5 };
  const readCaps = (): Record<string, number> => {
    if (!existsSync(cfg.capsPath)) return {};
    try {
      return JSON.parse(readFileSync(cfg.capsPath, "utf8")) as Record<string, number>;
    } catch {
      return {};
    }
  };
  const readCap = (kind: CapKind): number => {
    const v = readCaps()[kind];
    return typeof v === "number" && v >= 0 ? v : CAP_DEFAULTS[kind];
  };
  const writeCap = (kind: CapKind, n: number): void => {
    mkdirSync(dirname(cfg.capsPath), { recursive: true });
    writeFileSync(cfg.capsPath, JSON.stringify({ ...readCaps(), [kind]: n }, null, 2));
  };

  // "Run now" / IMMEDIATE mode: emit a run request as a file in the spool dir.
  // The board is a hardened, sandboxed service and must NOT execute run.sh
  // itself (no repo, no git push keys, no worktree perms) — so it only writes
  // the intent. A systemd.path twin of the nightly runner watches this dir and
  // executes `run.sh NB_ONLY_GOAL=<goal>` out-of-band. goalId is a vault folder
  // name (a slug); sanitize hard to keep this a filename, never a path.
  const requestRunNow = (goalId: string): void => {
    const safe = goalId.replace(/[^A-Za-z0-9._-]/g, "");
    if (!safe || safe === "." || safe === "..") return;
    mkdirSync(cfg.runNowSpoolDir, { recursive: true });
    writeFileSync(join(cfg.runNowSpoolDir, safe), `${safe}\n`);
  };

  // SR "re-investigate now": same hardened-board pattern — drop an <srId> file
  // in the SR spool; sr-gauntlet-runnow.path runs `run.sh --id <srId>` out of
  // band. srId is a Firestore doc id; sanitize hard to keep it a bare filename.
  const requestSrRunNow = (srId: string): void => {
    const safe = srId.replace(/[^A-Za-z0-9._-]/g, "");
    if (!safe || safe === "." || safe === "..") return;
    mkdirSync(cfg.srRunNowSpoolDir, { recursive: true });
    writeFileSync(join(cfg.srRunNowSpoolDir, safe), `${safe}\n`);
  };

  // Board-owned native execution: the hardened board runs the gates in-process,
  // then drops the item id in this spool. A privileged systemd.path twin drains
  // it by invoking `refinery-run-native --id <itemId>` (which builds + runs the
  // native executor and finalizes the item). Same hardened-board contract as the
  // run-now spools above — the board never spawns a worktree/git push itself.
  // itemId is a store filename slug; sanitize hard to keep it a bare filename.
  const requestNativeRunNow = (id: string): void => {
    const safe = id.replace(/[^A-Za-z0-9._-]/g, "");
    if (!safe || safe === "." || safe === "..") return;
    mkdirSync(cfg.nativeRunNowSpoolDir, { recursive: true });
    writeFileSync(join(cfg.nativeRunNowSpoolDir, safe), `${safe}\n`);
  };

  async function intake(text: string): Promise<void> {
    const enabled = catalog.enabled();
    const options = enabled.map((p) => ({ pipeline: p.pipeline, label: p.label }));
    // Triage is best-effort: if the LLM is unavailable (no key, claude binary
    // can't run in the hardened service, network down), the idea still lands in
    // the hopper as untriaged for manual promotion on the detail page. Intake
    // never fails.
    let decision = { pipeline: UNTRIAGED, confidence: 0, reason: "not triaged" };
    try {
      const llm = cfg.triageLlm ?? resolveLlm(cfg.triageProvider);
      decision = await triageSentence(text, options, llm);
    } catch (e) {
      decision = { pipeline: UNTRIAGED, confidence: 0, reason: `triage unavailable: ${(e as Error).message}` };
    }
    const pipeline = catalog.get(decision.pipeline);
    const firstStep = pipeline?.gates[0] ?? "triage";
    const id = `${slug(text)}-${Date.now()}`;
    await store.save(
      makeTriagedItem(id, text, decision, firstStep, cfg.clock, pipeline?.defaultTraits),
    );
    // Event-driven pipelines (e.g. incoming SR tickets) run on arrival; manual
    // pipelines (project-ideation) wait for the board's Run button.
    if (pipeline?.autoRun) void kickRun(id);
  }

  /** Hopper intake: capture a raw idea as UNTRIAGED (no triage — it stays an
   *  idea until promoted) and, when the vault is wired, append it to the brain's
   *  `## backlog` so the two stay in sync. The deterministic id keeps the
   *  round-trip (append → re-read by syncBrain) from echoing a duplicate. */
  async function intakeIdea(text: string): Promise<void> {
    const id = ideaId(text);
    if (!(await store.load(id))) {
      await store.save(makeIdeaItem({ id, text, section: "backlog", goalId: "(root)" }, cfg.clock));
    }
    if (cfg.vaultDir) appendBrainIdea(cfg.vaultDir, text);
  }

  /** The exit ramp for engine items: sweep passed items off the working board.
   *  Two triggers — (a) chain complete: the item's declared successor exists, so
   *  its spec has been consumed and the successor card carries the lineage;
   *  (b) aged out: passed and untouched for archiveAfterDays. Archived items
   *  stay in the store and render on /finished; any manual status move revives
   *  them. Best-effort like syncBrain — a sweep hiccup never 500s a render. */
  async function sweepArchive(): Promise<void> {
    try {
      const afterMs = (cfg.archiveAfterDays ?? 7) * 86_400_000;
      const items = await store.list();
      const now = Date.parse(cfg.clock());
      for (const item of items) {
        if (item.state !== "passed" || item.archived || item.pipeline === UNTRIAGED) continue;
        const next = catalog.get(item.pipeline)?.next;
        const chainComplete = next ? items.some((i) => i.id === `${item.id}-${next}`) : false;
        const lastAt = item.history.length ? Date.parse(item.history[item.history.length - 1]!.at) : NaN;
        const agedOut = Number.isFinite(lastAt) && Number.isFinite(now) && now - lastAt >= afterMs;
        if (!chainComplete && !agedOut) continue;
        await store.save({
          ...item,
          archived: true,
          archivedAt: cfg.clock(),
          history: [...item.history, {
            step: item.step ?? "archive", status: "entered", at: cfg.clock(),
            note: chainComplete ? "archived: chain complete (successor exists)" : "archived: passed and aged out",
          }],
        });
      }
    } catch {
      /* best-effort: the board renders whatever state the sweep reached */
    }
  }

  /** Reconcile the store against the brain vault's ideas (best-effort, like
   *  intake: a vault read/write hiccup must never 500 a page render). */
  async function syncBrain(): Promise<void> {
    if (!cfg.vaultDir) return;
    try {
      await syncBrainIdeas(store, cfg.vaultDir, cfg.clock);
    } catch {
      /* best-effort: the hopper still renders whatever is already in the store */
    }
  }

  /** Declarative handoff: create (and kick) the successor pipeline's item from a
   *  finished parent. The chain link is `pipeline.next`; this is the deterministic
   *  realization of it. Idempotent by a deterministic successor id
   *  (`${parent.id}-${nextPipelineId}`) so a re-trigger (auto + one-shot, or a
   *  re-run) never duplicates. The successor carries the parent's developed spec,
   *  repo, and domain so the builder has everything it needs. If the next pipeline
   *  isn't in the catalog, or the successor already exists, this no-ops. */
  async function chainTo(parent: Item, nextPipelineId: string): Promise<void> {
    const next = catalog.get(nextPipelineId);
    if (!next) return; // unknown successor pipeline — nothing to chain to
    const successorId = `${parent.id}-${nextPipelineId}`;
    if (await store.load(successorId)) return; // already chained — idempotent
    const parentPayload = (parent.payload && typeof parent.payload === "object" ? parent.payload : {}) as Record<string, unknown>;
    const execResult = (parentPayload.executorResult && typeof parentPayload.executorResult === "object" ? parentPayload.executorResult : {}) as Record<string, unknown>;
    const output = (execResult.output && typeof execResult.output === "object" ? execResult.output : {}) as Record<string, unknown>;
    const spec = (output.spec && typeof output.spec === "object" ? output.spec : undefined) as Record<string, unknown> | undefined;
    // The build ask = the spec's deliverable (what to build) or its goal as a
    // fallback; then the parent's raw input.
    const parentTitle = typeof parentPayload.title === "string" ? parentPayload.title : parent.id;
    const buildAsk = (spec && typeof spec.deliverable === "string" && spec.deliverable)
      || (spec && typeof spec.goal === "string" && spec.goal)
      || (typeof parentPayload.input === "string" ? parentPayload.input : "")
      || parentTitle;
    const successor: Item = {
      id: successorId,
      pipeline: nextPipelineId,
      step: next.gates[0],
      state: "pending",
      payload: {
        title: `build: ${parentTitle}`,
        input: buildAsk,
        spec,
        repo: parentPayload.repo,
        // Inherit the parent's domain identity: an explicit override wins, else
        // the parent's classified domain — otherwise the successor's input (the
        // spec deliverable, no "prefix:" head) always classifies to Misc.
        domain: typeof parentPayload.domain === "string" ? parentPayload.domain : domainOf(parent, domains).key,
        parent: parent.id,
        chain: parent.chain,
        traits: next.defaultTraits,
      },
      chain: parent.chain,
      history: [{ step: "triage", status: "entered", at: cfg.clock(), note: `chained from ${parent.id}` }],
    };
    await store.save(successor);
    // Kick the successor: for a native `build` successor this runs the gates
    // in-board then spools native execution (the existing native branch). A
    // missing repo doesn't crash — the native runner fails clean asking for one.
    await kickRun(successorId);
  }

  /** Run one triaged engine item through its pipeline. The board branches on the
   *  pipeline's terminal executor:
   *   - `spec`   → run gates + the spec executor IN-PROCESS (project-ideation);
   *     synthesize+write a spec. Unchanged from the CLI's run-once core.
   *   - `native` → the hardened board must NOT spawn a worktree / git push. It
   *     runs ONLY the gates in-process; on a clean pass it marks the item
   *     `running`, then SPOOLS an execute request that the privileged
   *     `refinery-run-native` unit drains. External-gauntlet pipelines are
   *     refused here (the double-execution guard).
   *   - anything else fails loud so the item parks with a clear reason.
   *  Read-only mirror items aren't in the store, so load() returns null and this
   *  no-ops. Throws are surfaced by the caller. */
  async function runItem(id: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const pipeline = catalog.get(item.pipeline);
    if (!pipeline) return; // untriaged / unknown pipeline — nothing to run
    const payload = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
    const input = typeof payload.input === "string" ? payload.input : "";
    const llm = cfg.runLlm ?? resolveLlm(pipeline.llmProvider ?? cfg.triageProvider);

    if (pipeline.executors.includes("spec")) {
      const result = await runPipelineOnce(
        { id, input },
        { pipeline, gates: gateList(llm), integrate: makeSpecExecutor({ scratchDir: cfg.scratchDir }, llm), store, clock: cfg.clock },
      );
      // Declarative chaining: a clean spec pass hands off to pipeline.next IFF
      // the item opted in (item.chain). Re-load the item so we read the persisted
      // chain flag + the executorResult the spec just wrote. Only the spec
      // (in-board) path chains; native is terminal. A parent without payload.repo
      // still chains (the successor fails clean asking for a repo) — it must not
      // crash runItem.
      if (pipeline.next && !result.parked) {
        const saved = await store.load(id);
        if (saved && saved.chain === true) await chainTo(saved, pipeline.next);
      }
      return;
    }

    if (pipeline.executors.includes("native")) {
      if (EXTERNAL_GAUNTLET_PIPELINES.has(pipeline.pipeline)) {
        throw new Error(
          `pipeline "${pipeline.pipeline}" is owned by an external gauntlet — trigger it via the run-now spool, not board native execution`,
        );
      }
      // Gates only — the board never builds or runs the native executor. runPass
      // saves the item itself, including the parked/failed case.
      const result = await runPass(item, pipeline, gateList(llm), { store, clock: cfg.clock });
      if (result.stoppedBy) return; // parked/failed at a gate — already saved
      // Clean pass: mark it running and spool the execute request for the
      // privileged runner to drain.
      await store.save({
        ...result.item,
        state: "running",
        parkedReason: undefined,
        history: [
          ...result.item.history,
          { step: "native", status: "running", at: cfg.clock(), note: "queued for native execution" },
        ],
      });
      requestNativeRunNow(id);
      return;
    }

    throw new Error(
      `no board executor wired for pipeline "${pipeline.pipeline}" (executors: ${pipeline.executors.join(", ")})`,
    );
  }

  /** Fire-and-forget a run: mark the item running for immediate UI feedback,
   *  then process in the background. A crash mid-run leaves it failed-reviewable
   *  rather than stuck running. */
  async function kickRun(id: string): Promise<void> {
    const item = await store.load(id);
    if (!item || !catalog.get(item.pipeline) || item.state === "running") return;
    await store.save({ ...item, state: "running", parkedReason: undefined });
    // Returned so tests can await completion; production calls `void kickRun(id)`
    // so the HTTP request / intake doesn't block on the (slow) pipeline.
    return runItem(id).catch(async (e) => {
      const cur = await store.load(id);
      if (cur) {
        await store.save({
          ...cur,
          state: "failed",
          parkedReason: `run error: ${(e as Error).message}`,
          history: [...cur.history, { step: cur.step ?? "run", status: "failed", at: cfg.clock(), note: `run error: ${(e as Error).message}` }],
        });
      }
    });
  }

  async function amend(id: string, note: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const payload = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
    const amendments = Array.isArray(payload.amendments) ? payload.amendments : [];
    await store.save({
      ...item,
      state: "pending",
      parkedReason: undefined,
      payload: { ...payload, amendments: [...amendments, note] },
      history: [...item.history, { step: item.step ?? "triage", status: "entered", at: cfg.clock(), note }],
    });
  }

  async function doRewind(id: string, toStep: string, note: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    await store.save(rewind(item, toStep, note, { clock: cfg.clock }));
  }

  /** Manual lane move from the board: set an engine item's state directly (a
   *  human override of the pipeline-driven status), logged to history. No-ops
   *  for read-only mirror items (not in the store). */
  async function setStatus(id: string, status: string): Promise<void> {
    const valid: Item["state"][] = ["pending", "running", "passed", "parked", "failed"];
    if (!valid.includes(status as Item["state"])) return;
    const s = status as Item["state"];
    const item = await store.load(id);
    if (!item) return;
    await store.save({
      ...item,
      state: s,
      // A manual lane move revives an archived item — the human is explicitly
      // putting it back to work, so it returns to the board.
      archived: undefined,
      archivedAt: undefined,
      parkedReason: s === "parked" ? (item.parkedReason ?? "manually parked on the board") : undefined,
      history: [...item.history, { step: item.step ?? "triage", status: s, at: cfg.clock(), note: "status set on board" }],
    });
  }

  async function setNightly(id: string, nightly: boolean): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    await store.save({ ...item, schedule: nightly ? "nightly" : "now", schedulePriority: item.schedulePriority ?? 0 });
  }

  async function bumpNightly(id: string, dir: "up" | "down"): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const delta = dir === "up" ? 1 : -1;
    await store.save({ ...item, schedulePriority: (item.schedulePriority ?? 0) + delta });
  }

  async function deleteItem(id: string): Promise<void> {
    const item = await store.load(id);
    // A brain-sourced idea: remove its line from _ideas.md too, so deleting on
    // the board reflects back into the vault (the source of truth).
    if (item && isBrainIdea(item) && cfg.vaultDir) {
      const text = (item.payload as { input?: unknown }).input;
      if (typeof text === "string") removeBrainIdea(cfg.vaultDir, text);
    }
    await store.delete(id); // no-op for read-only mirror items (not in the store)
  }

  /** Hopper idea stage move (Captured → Shaping → Ready). Stages live in `stage`
   *  on untriaged items; only untriaged items have a hopper stage. */
  async function setStage(id: string, toStage: string): Promise<void> {
    if (!HOPPER_STAGE_KEYS.includes(toStage)) return;
    const item = await store.load(id);
    if (!item || item.pipeline !== UNTRIAGED) return;
    await store.save({
      ...item,
      stage: toStage,
      history: [...item.history, { step: toStage, status: "entered", at: cfg.clock(), note: "stage moved on board" }],
    });
  }

  /** Manual domain override (the color/tag identity axis). Stored in the payload;
   *  a render-time classifier picks the default from the idea text otherwise. */
  async function setDomain(id: string, domain: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const payload = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
    await store.save({ ...item, payload: { ...payload, domain } });
  }

  // Bind the target repo a native pipeline (app-refinement) runs against. The
  // native runner needs this (or REFINERY_NATIVE_REPO) to build the worktree;
  // without it the item fails cleanly with "needs a target repo".
  async function setRepo(id: string, repo: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const payload = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
    const trimmed = repo.trim();
    await store.save({ ...item, payload: { ...payload, repo: trimmed || undefined } });
  }

  /** Per-item auto-advance toggle. When on, a clean pass of a pipeline that
   *  declares `next` auto-creates+kicks the successor (idea → spec → build runs
   *  end to end). Off (default) stops at this pipeline's result for review. */
  async function setChain(id: string, on: boolean): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    await store.save({ ...item, chain: on });
  }

  /** One-shot build: hand a completed (spec-bearing) item off to its build
   *  pipeline now, regardless of the auto-advance toggle. No-ops if the item has
   *  no developed spec yet (nothing to build). Uses the item's pipeline.next, or
   *  falls back to "build". */
  async function buildNow(id: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const payload = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
    const execResult = (payload.executorResult && typeof payload.executorResult === "object" ? payload.executorResult : {}) as Record<string, unknown>;
    const output = (execResult.output && typeof execResult.output === "object" ? execResult.output : {}) as Record<string, unknown>;
    if (!output.spec || typeof output.spec !== "object") return; // no spec → nothing to build
    const nextId = catalog.get(item.pipeline)?.next ?? "build";
    await chainTo(item, nextId);
  }

  /** Promote an idea into a refinement pipeline. `schedule` chooses how it runs:
   *  "immediate" kicks the pipeline now; "nightly" flags it for the overnight
   *  batch (no immediate run). Anything else just promotes (manual run later). */
  async function promote(id: string, pipelineId: string, schedule = ""): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const pipeline = catalog.get(pipelineId);
    if (!pipeline) return;
    await store.save({
      ...item,
      pipeline: pipelineId,
      step: pipeline.gates[0] ?? "triage",
      stage: undefined,
      state: "pending",
      parkedReason: undefined,
      schedule: schedule === "nightly" ? "nightly" : item.schedule,
      history: [...item.history, { step: pipeline.gates[0] ?? "triage", status: "entered", at: cfg.clock(), note: `promoted to ${pipelineId}${schedule ? ` (${schedule})` : ""}` }],
    });
    // Brain-sourced idea → record the promotion in the vault: cut it from
    // backlog/drafted and file it under `## promoted` (annotated with the pipeline).
    if (isBrainIdea(item) && cfg.vaultDir) {
      const text = (item.payload as { input?: unknown }).input;
      if (typeof text === "string") promoteBrainIdea(cfg.vaultDir, text, pipelineId, cfg.clock);
    }
    // Immediate scheduling: run the pipeline now (same as the /run route — the
    // shell marks it running and processes; the redirect happens after).
    if (schedule === "immediate") await kickRun(id);
  }

  const server = createServer((req, res) => {
    void (async () => {
      try {
        const url = (req.url ?? "/").split("?")[0]!;
        const method = req.method ?? "GET";

        if (method === "GET" && url === "/healthz") {
          res.writeHead(200, { "content-type": "text/plain" });
          res.end("ok");
          return;
        }
        // Read-only mirror of the live gauntlets: nightly-builds vault cards +
        // sr_gauntlet investigations.
        const mirror = (): Item[] => [
          ...(cfg.vaultDir ? nightlyCardProjects(cfg.vaultDir) : []),
          ...(cfg.srGauntletDir ? srInvestigationProjects(cfg.srGauntletDir) : []),
        ];

        if (method === "GET" && url === "/hopper") {
          // /hopper folded into the combined board (Hopper stacked over
          // Development). Redirect so old links / bookmarks still land somewhere.
          return redirectTo(res, "/");
        }
        if (method === "GET" && url === "/") {
          // The combined board: Hopper (untriaged ideas) stacked over Development
          // (triaged projects). Pull the latest brain ideas in first (the interval
          // sync in serve.ts handles the idle case), then run the archive sweep
          // so finished work leaves the board instead of piling up in Done.
          await syncBrain();
          await sweepArchive();
          const [items, profiles, enabled] = [await store.list(), catalog.list(), catalog.enabled()];
          // Server-side board filter (?domain=&pipeline=&q=) — plain GET params,
          // no client JS. Applies to ideas, projects and mirror cards alike.
          const params = new URLSearchParams((req.url ?? "").split("?")[1] ?? "");
          const filter = {
            domain: (params.get("domain") ?? "").trim(),
            pipeline: (params.get("pipeline") ?? "").trim(),
            q: (params.get("q") ?? "").trim(),
          };
          const matches = (i: Item): boolean => {
            if (filter.domain && domainOf(i, domains).key !== filter.domain) return false;
            if (filter.pipeline && i.pipeline !== filter.pipeline) return false;
            if (filter.q) {
              const pl = (i.payload && typeof i.payload === "object" ? i.payload : {}) as Record<string, unknown>;
              const hay = `${i.id} ${typeof pl.title === "string" ? pl.title : ""} ${typeof pl.input === "string" ? pl.input : ""}`.toLowerCase();
              if (!hay.includes(filter.q.toLowerCase())) return false;
            }
            return true;
          };
          const ideas = items.filter((i) => i.pipeline === UNTRIAGED).filter(matches);
          // Development: store projects + nightly-build mirror cards (SRs have
          // their own page). Archived items live on /finished, not here.
          const projects = [
            ...items.filter((i) => i.pipeline !== UNTRIAGED && i.archived !== true),
            ...mirror().filter((m) => !m.id.startsWith(SR_PREFIX)),
          ].filter(matches);
          const archivedCount = items.filter((i) => i.archived === true).length;
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderBoard(ideas, projects, profiles, enabled, domains, { filter, archivedCount }));
          return;
        }
        if (method === "GET" && url === "/nightly") {
          const [items, profiles, enabled] = [await store.list(), catalog.list(), catalog.enabled()];
          const flagged = [
            ...items.filter((i) => i.schedule === "nightly"),
            ...mirror().filter((m) => m.id.startsWith(NB_PREFIX)),
          ].sort((a, b) => (b.schedulePriority ?? 0) - (a.schedulePriority ?? 0) || a.id.localeCompare(b.id));
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderNightly(flagged, readCap("nightly"), profiles, enabled, domains));
          return;
        }
        if (method === "GET" && url === "/finished") {
          // Graduated nightly-build projects (off the gauntlet) + archived
          // engine items (the board's exit ramp), newest archive first.
          const [profiles, enabled] = [catalog.list(), catalog.enabled()];
          const finished = cfg.vaultDir ? finishedProjects(cfg.vaultDir) : [];
          const archived = (await store.list())
            .filter((i) => i.archived === true)
            .sort((a, b) => (b.archivedAt ?? "").localeCompare(a.archivedAt ?? ""));
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderFinished(finished, profiles, enabled, domains, archived));
          return;
        }
        if (method === "GET" && url === "/reference") {
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderReference(catalog.list()));
          return;
        }
        if (method === "GET" && url === "/reviews") {
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderReviews(await listReviews()));
          return;
        }
        if (method === "GET" && url === "/sr") {
          const profiles = catalog.list();
          const srs = mirror()
            .filter((m) => m.id.startsWith(SR_PREFIX))
            .sort((a, b) => b.id.localeCompare(a.id));
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderSr(srs, readCap("sr"), profiles, domains));
          return;
        }
        if (method === "GET" && url.startsWith("/project/")) {
          const id = decodeURIComponent(url.slice("/project/".length));
          // Finished projects live off the gauntlet (own vault dir), so they're
          // not in mirror() — look them up directly by their nbf: id.
          const finishedItem = id.startsWith(FINISHED_PREFIX) && cfg.vaultDir
            ? finishedProjects(cfg.vaultDir).find((m) => m.id === id) ?? null
            : null;
          const item = (await store.load(id)) ?? mirror().find((m) => m.id === id) ?? finishedItem;
          if (!item) {
            res.writeHead(404, { "content-type": "text/plain" });
            res.end("no such project");
            return;
          }
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          if (id.startsWith(FINISHED_PREFIX)) {
            res.end(renderFinishedProject(item));
          } else if (id.startsWith(NB_PREFIX)) {
            res.end(renderNightlyProject(item));
          } else if (id.startsWith(SR_PREFIX) && cfg.srGauntletDir) {
            // SR items render in the SR2-style tabbed layout (Gameplan/Thread/Details).
            const run = typeof (item.payload as { run?: unknown }).run === "string"
              ? (item.payload as { run: string }).run
              : "";
            res.end(renderSrDetail(item, {
              gameplan: readRunFile(cfg.srGauntletDir, run, "REPORT.md"),
              thread: readRunFile(cfg.srGauntletDir, run, "sr.md"),
              context: readRunFile(cfg.srGauntletDir, run, "context.md"),
            }));
          } else {
            res.end(renderProjectDetail(item, catalog.list(), catalog.enabled(), domains));
          }
          return;
        }
        if (method === "GET" && url.startsWith("/report/")) {
          const id = decodeURIComponent(url.slice("/report/".length));
          let report: string | null = null;
          let title = id;
          if (id.startsWith("nbrun:") && cfg.vaultDir) {
            // a nightly-build step's run dir (passed from the project detail)
            const run = id.slice("nbrun:".length);
            report = readReport(cfg.vaultDir, run);
            title = run;
          } else {
            const item = mirror().find((m) => m.id === id);
            const run = item && typeof (item.payload as { run?: unknown }).run === "string"
              ? (item.payload as { run: string }).run
              : "";
            if (item && run && id.startsWith(SR_PREFIX) && cfg.srGauntletDir) {
              report = readReport(cfg.srGauntletDir, run);
            }
            title = item ? String((item.payload as { title?: unknown }).title ?? id) : id;
          }
          res.writeHead(report ? 200 : 404, { "content-type": "text/html; charset=utf-8" });
          res.end(renderReport(title, report));
          return;
        }

        if (method === "POST") {
          const body = await readBody(req);
          const id = body.get("id") ?? "";
          // Cards post a `back` path so an action redirects to the board the user
          // is on (the change is visible in place); detail-page forms omit it and
          // fall back to the project detail. Only same-origin paths are honored.
          const rawBack = body.get("back") ?? "";
          const back = rawBack.startsWith("/") && !rawBack.startsWith("//") ? rawBack : "";
          const afterEdit = back || `/project/${encodeURIComponent(id)}`;
          if (url === "/intake") {
            const text = (body.get("text") ?? "").trim();
            if (text) await intakeIdea(text);
            return redirectTo(res, "/hopper");
          }
          if (url === "/amend") {
            await amend(id, (body.get("note") ?? "").trim());
            return redirectTo(res, afterEdit);
          }
          if (url === "/rewind") {
            await doRewind(id, body.get("toStep") ?? "", (body.get("note") ?? "").trim());
            return redirectTo(res, afterEdit);
          }
          if (url === "/status") {
            // Manual lane move from a board card (human override of pipeline status).
            await setStatus(id, body.get("status") ?? "");
            return redirectTo(res, back || "/");
          }
          if (url === "/stage") {
            // Hopper idea maturation move (Captured → Shaping → Ready).
            await setStage(id, body.get("toStage") ?? "");
            return redirectTo(res, back || "/hopper");
          }
          if (url === "/domain") {
            // Manual domain (color + tag) override.
            await setDomain(id, body.get("domain") ?? "");
            return redirectTo(res, back || "/hopper");
          }
          if (url === "/promote") {
            // schedule: "immediate" runs the pipeline now; "nightly" flags it for
            // the overnight batch; "" just promotes (manual run later).
            await promote(id, body.get("pipeline") ?? "", body.get("schedule") ?? "");
            return redirectTo(res, afterEdit);
          }
          if (url === "/set-repo") {
            // Bind the target repo for a native pipeline (app-refinement).
            await setRepo(id, body.get("repo") ?? "");
            return redirectTo(res, afterEdit);
          }
          if (url === "/chain") {
            // Per-item auto-advance toggle (spec → build hands off automatically).
            await setChain(id, body.get("on") === "true");
            return redirectTo(res, afterEdit);
          }
          if (url === "/build") {
            // One-shot: hand this completed spec off to its build pipeline now.
            await buildNow(id);
            return redirectTo(res, afterEdit);
          }
          if (url === "/run") {
            // Run the item's pipeline now (gates → effector). Fire-and-forget so
            // the request returns immediately; the board shows "running" and the
            // result on the next refresh.
            await kickRun(id);
            return redirectTo(res, afterEdit);
          }
          if (url === "/delete") {
            await deleteItem(id);
            return redirectTo(res, back || "/");
          }
          if (url === "/card/queue") {
            // GUI for the Phase-4 gate: queue/unqueue a project's next step in
            // the vault. queueNextStep queues the next pending step (draft OR
            // blocked — a blocked step is a deliberate force-queue override, so
            // nothing is ever a dead end). In IMMEDIATE mode, queuing also kicks
            // a targeted run now; in NIGHTLY mode run.sh @ 01:30 executes.
            const goalId = parseNbId(id);
            if (cfg.vaultDir && goalId) {
              if (body.get("to") === "queued") {
                queueNextStep(cfg.vaultDir, goalId);
                if (readProjectMode(cfg.vaultDir, goalId) === "immediate") requestRunNow(goalId);
              } else {
                unqueueStep(cfg.vaultDir, goalId);
              }
            }
            return redirectTo(res, afterEdit);
          }
          if (url === "/card/run-now") {
            // Explicit immediate execution of one project, regardless of mode.
            // Ensure a step is queued (queue the next pending one only if none is
            // already in flight), then drop the run request.
            const goalId = parseNbId(id);
            if (cfg.vaultDir && goalId) {
              if (!hasActiveStep(cfg.vaultDir, goalId)) queueNextStep(cfg.vaultDir, goalId);
              if (hasActiveStep(cfg.vaultDir, goalId)) requestRunNow(goalId);
            }
            return redirectTo(res, afterEdit);
          }
          if (url === "/card/mode") {
            // Persistent NIGHTLY ↔ IMMEDIATE toggle (written to _goal.md). The
            // switch itself never executes anything — it only changes what a
            // future queue does. Run-now stays the explicit immediate trigger.
            const goalId = parseNbId(id);
            const mode = body.get("mode") === "immediate" ? "immediate" : "nightly";
            if (cfg.vaultDir && goalId) setProjectMode(cfg.vaultDir, goalId, mode);
            return redirectTo(res, afterEdit);
          }
          if (url === "/card/sendback") {
            // Send a finished project back to the gauntlet, optionally with an
            // amendment (a fresh queued step). reopenProject moves the folder
            // out of _finished/ and writes the amendment step; the project is
            // back in flight, so we redirect to the gauntlet board (back).
            const goalId = parseFinishedId(id) ?? id;
            const amendment = (body.get("amendment") ?? "").trim();
            if (cfg.vaultDir && goalId) reopenProject(cfg.vaultDir, goalId, amendment);
            return redirectTo(res, back || "/nightly");
          }
          if (url === "/nightly/toggle") {
            await setNightly(id, body.get("nightly") === "true");
            return redirectTo(res, afterEdit);
          }
          if (url === "/nightly/bump") {
            const dir = body.get("dir") === "up" ? "up" : "down";
            await bumpNightly(id, dir);
            return redirectTo(res, "/nightly");
          }
          if (url === "/nightly/config") {
            const n = Number(body.get("maxPerNight"));
            if (Number.isFinite(n) && n >= 0) writeCap("nightly", Math.floor(n));
            return redirectTo(res, "/nightly");
          }
          if (url === "/sr/config") {
            const n = Number(body.get("maxPerNight"));
            if (Number.isFinite(n) && n >= 0) writeCap("sr", Math.floor(n));
            return redirectTo(res, "/sr");
          }
          if (url === "/sr/run-now") {
            // Force a fresh investigation of one SR now. The SR mirror item
            // carries the real Firestore srId in its payload; the form passes it
            // directly (mirror items aren't in the store). The board only writes
            // the spool request — sr-gauntlet-runnow.path runs run.sh --id.
            const srId = (body.get("srId") ?? "").trim();
            if (srId) requestSrRunNow(srId);
            return redirectTo(res, id ? `/project/${encodeURIComponent(id)}` : "/sr");
          }
          if (url === "/profiles/toggle") {
            const pipelineId = body.get("pipeline") ?? "";
            if (pipelineId) catalog.setEnabled(pipelineId, body.get("enabled") === "true");
            return redirectTo(res, "/");
          }
        }
        res.writeHead(404, { "content-type": "text/plain" });
        res.end("not found");
      } catch (e) {
        res.writeHead(500, { "content-type": "text/plain" });
        res.end(`refinery error: ${(e as Error).message}`);
      }
    })();
  });

  return { server, store, catalog, domains, intake, intakeIdea, syncBrain, sweepArchive, amend, doRewind, setStatus, setStage, setDomain, setRepo, setChain, buildNow, chainTo, setNightly, bumpNightly, promote, deleteItem, runItem, kickRun, requestSrRunNow, requestNativeRunNow };
}
