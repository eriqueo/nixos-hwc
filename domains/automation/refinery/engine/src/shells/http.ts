// HTTP shell over the engine core (hexagonal: a shell translating inbound HTTP
// into core calls). Serves the Gauntlet / Hopper / Nightly pages, a per-project
// detail+edit page, and the intake/amend/rewind/promote/nightly endpoints,
// operating on the MarkdownItemStore + ProfileCatalog + triage. Engine-only
// items. All config late-bound from the environment.

import { createServer, IncomingMessage, ServerResponse } from "node:http";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { Item, ItemEffector, Profile } from "../contracts.js";
import { MarkdownItemStore } from "../stores/markdown-store.js";
import { ProfileCatalog } from "../profiles/catalog.js";
import { resolveLlm } from "../adapters/resolver.js";
import { triageSentence, makeTriagedItem, UNTRIAGED } from "../triage.js";
import { rewind } from "../runner.js";
import { gateList } from "../gates/index.js";
import { makeWriteSpecEffector } from "../effectors/write-spec.js";
import { runGenreOnce } from "../cli/run-once.js";
import { LlmPort } from "../gates/llm-port.js";
import { nightlyCardProjects, queueNextStep, unqueueStep, parseNbId, readReport, hasActiveStep, readProjectMode, setProjectMode, NB_PREFIX } from "../sources/nightly-cards.js";
import { srInvestigationProjects, readRunFile, SR_PREFIX } from "../sources/sr-investigations.js";
import { renderGauntlet, renderHopperPage, renderNightly, renderNightlyProject, renderSr, renderSrDetail, renderProjectDetail, renderReport } from "./render.js";

export interface HttpShellConfig {
  port: number;
  itemsDir: string;
  profilesDir: string;
  profileStatePath: string;
  capsPath: string; // per-gauntlet "max per run" caps, written by the GUI
  scratchDir: string; // where the write-spec effector drops developed specs
  triageProvider: string;
  vaultDir?: string; // brain vault — nightly-builds card mirror + queue write-back
  srGauntletDir?: string; // sr_gauntlet dir — SR investigation mirror
  runNowSpoolDir: string; // "Run now" / IMMEDIATE drops a <goal> request file here; a systemd.path twin of run.sh drains it
  clock: () => string;
  triageLlm?: LlmPort; // test override; production resolves from triageProvider
  runLlm?: LlmPort; // test override for the pipeline runner; prod resolves per profile
}

export function configFromEnv(): HttpShellConfig {
  const home = process.env.HOME ?? "/tmp";
  const base = `${home}/.local/state/refinery`;
  return {
    port: Number(process.env.REFINERY_PORT || 8060),
    itemsDir: process.env.REFINERY_ITEMS_DIR || `${base}/items`,
    profilesDir: process.env.REFINERY_PROFILES_DIR || "profiles",
    profileStatePath: process.env.REFINERY_PROFILE_STATE || `${base}/profiles.json`,
    capsPath: process.env.REFINERY_CAPS_FILE || `${base}/caps.json`,
    scratchDir: process.env.REFINERY_SCRATCH_DIR || `${base}/specs`,
    triageProvider: process.env.REFINERY_TRIAGE_PROVIDER || "claude-cli",
    vaultDir: process.env.REFINERY_VAULT_DIR,
    srGauntletDir: process.env.REFINERY_SR_GAUNTLET_DIR,
    runNowSpoolDir: process.env.REFINERY_RUNNOW_SPOOL || `${base}/run-now`,
    clock: () => new Date().toISOString(),
  };
}

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
  const catalog = new ProfileCatalog({ dir: cfg.profilesDir, statePath: cfg.profileStatePath });

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

  async function intake(text: string): Promise<void> {
    const enabled = catalog.enabled();
    const options = enabled.map((p) => ({ genre: p.genre, label: p.label }));
    // Triage is best-effort: if the LLM is unavailable (no key, claude binary
    // can't run in the hardened service, network down), the idea still lands in
    // the hopper as untriaged for manual promotion on the detail page. Intake
    // never fails.
    let decision = { genre: UNTRIAGED, confidence: 0, reason: "not triaged" };
    try {
      const llm = cfg.triageLlm ?? resolveLlm(cfg.triageProvider);
      decision = await triageSentence(text, options, llm);
    } catch (e) {
      decision = { genre: UNTRIAGED, confidence: 0, reason: `triage unavailable: ${(e as Error).message}` };
    }
    const profile = catalog.get(decision.genre);
    const firstPhase = profile?.gates[0] ?? "triage";
    const id = `${slug(text)}-${Date.now()}`;
    await store.save(makeTriagedItem(id, text, decision, firstPhase, cfg.clock));
    // Event-driven genres (e.g. incoming SR tickets) run the pipeline on
    // arrival; manual genres (project-ideation) wait for the board's Run button.
    if (profile?.autoRun) void kickRun(id);
  }

  /** Resolve the genre's integrate effector. write-spec is wired; other
   *  effectors (e.g. SR's `execute`) aren't board-runnable yet — fail loud so
   *  the item parks with a clear reason rather than silently no-op'ing. */
  function resolveEffector(profile: Profile, llm: LlmPort): ItemEffector {
    if (profile.effectors.includes("write-spec")) {
      return makeWriteSpecEffector({ scratchDir: cfg.scratchDir }, llm);
    }
    throw new Error(
      `no board effector wired for genre "${profile.genre}" (effectors: ${profile.effectors.join(", ")})`,
    );
  }

  /** Run one triaged engine item through its profile's gate pipeline + effector
   *  (the same core the CLI uses). Read-only mirror items aren't in the store,
   *  so load() returns null and this no-ops. Throws are surfaced by the caller. */
  async function runItem(id: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const profile = catalog.get(item.genre);
    if (!profile) return; // untriaged / unknown genre — nothing to run
    const payload = (item.payload && typeof item.payload === "object" ? item.payload : {}) as Record<string, unknown>;
    const input = typeof payload.input === "string" ? payload.input : "";
    const llm = cfg.runLlm ?? resolveLlm(profile.llmProvider ?? cfg.triageProvider);
    await runGenreOnce(
      { id, input },
      { profile, gates: gateList(llm), integrate: resolveEffector(profile, llm), store, clock: cfg.clock },
    );
  }

  /** Fire-and-forget a run: mark the item running for immediate UI feedback,
   *  then process in the background. A crash mid-run leaves it failed-reviewable
   *  rather than stuck running. */
  async function kickRun(id: string): Promise<void> {
    const item = await store.load(id);
    if (!item || !catalog.get(item.genre) || item.phaseStatus === "running") return;
    await store.save({ ...item, phaseStatus: "running", parkedReason: undefined });
    // Returned so tests can await completion; production calls `void kickRun(id)`
    // so the HTTP request / intake doesn't block on the (slow) pipeline.
    return runItem(id).catch(async (e) => {
      const cur = await store.load(id);
      if (cur) {
        await store.save({
          ...cur,
          phaseStatus: "failed",
          parkedReason: `run error: ${(e as Error).message}`,
          history: [...cur.history, { phase: cur.phase, status: "failed", at: cfg.clock(), note: `run error: ${(e as Error).message}` }],
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
      phaseStatus: "pending",
      parkedReason: undefined,
      payload: { ...payload, amendments: [...amendments, note] },
      history: [...item.history, { phase: item.phase, status: "entered", at: cfg.clock(), note }],
    });
  }

  async function doRewind(id: string, toPhase: string, note: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    await store.save(rewind(item, toPhase, note, { clock: cfg.clock }));
  }

  async function setNightly(id: string, nightly: boolean): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    await store.save({ ...item, nightly, nightlyPriority: item.nightlyPriority ?? 0 });
  }

  async function bumpNightly(id: string, dir: "up" | "down"): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const delta = dir === "up" ? 1 : -1;
    await store.save({ ...item, nightlyPriority: (item.nightlyPriority ?? 0) + delta });
  }

  async function deleteItem(id: string): Promise<void> {
    await store.delete(id); // no-op for read-only mirror items (not in the store)
  }

  async function promote(id: string, genre: string): Promise<void> {
    const item = await store.load(id);
    if (!item) return;
    const profile = catalog.get(genre);
    if (!profile) return;
    await store.save({
      ...item,
      genre,
      phase: profile.gates[0] ?? "triage",
      phaseStatus: "pending",
      parkedReason: undefined,
      history: [...item.history, { phase: profile.gates[0] ?? "triage", status: "entered", at: cfg.clock(), note: `promoted to ${genre}` }],
    });
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

        if (method === "GET" && (url === "/" || url === "/hopper")) {
          const [items, profiles] = [await store.list(), catalog.list()];
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          if (url === "/hopper") {
            res.end(renderHopperPage(items.filter((i) => i.genre === UNTRIAGED), profiles));
          } else {
            // Gauntlet: store projects + nightly-build mirror cards (SRs have their own page).
            const projects = [
              ...items.filter((i) => i.genre !== UNTRIAGED),
              ...mirror().filter((m) => !m.id.startsWith(SR_PREFIX)),
            ];
            res.end(renderGauntlet(projects, profiles));
          }
          return;
        }
        if (method === "GET" && url === "/nightly") {
          const [items, profiles] = [await store.list(), catalog.list()];
          const flagged = [
            ...items.filter((i) => i.nightly),
            ...mirror().filter((m) => m.id.startsWith(NB_PREFIX)),
          ].sort((a, b) => (b.nightlyPriority ?? 0) - (a.nightlyPriority ?? 0) || a.id.localeCompare(b.id));
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderNightly(flagged, readCap("nightly"), profiles));
          return;
        }
        if (method === "GET" && url === "/sr") {
          const profiles = catalog.list();
          const srs = mirror()
            .filter((m) => m.id.startsWith(SR_PREFIX))
            .sort((a, b) => b.id.localeCompare(a.id));
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          res.end(renderSr(srs, readCap("sr"), profiles));
          return;
        }
        if (method === "GET" && url.startsWith("/project/")) {
          const id = decodeURIComponent(url.slice("/project/".length));
          const item = (await store.load(id)) ?? mirror().find((m) => m.id === id) ?? null;
          if (!item) {
            res.writeHead(404, { "content-type": "text/plain" });
            res.end("no such project");
            return;
          }
          res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
          if (id.startsWith(NB_PREFIX)) {
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
            res.end(renderProjectDetail(item, catalog.list(), catalog.enabled()));
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
          if (url === "/intake") {
            const text = (body.get("text") ?? "").trim();
            if (text) await intake(text);
            return redirectTo(res, "/hopper");
          }
          if (url === "/amend") {
            await amend(id, (body.get("note") ?? "").trim());
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
          }
          if (url === "/rewind") {
            await doRewind(id, body.get("toPhase") ?? "", (body.get("note") ?? "").trim());
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
          }
          if (url === "/promote") {
            await promote(id, body.get("genre") ?? "");
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
          }
          if (url === "/run") {
            // Run the item's pipeline now (gates → effector). Fire-and-forget so
            // the request returns immediately; the board shows "running" and the
            // result on the next refresh.
            await kickRun(id);
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
          }
          if (url === "/delete") {
            await deleteItem(id);
            return redirectTo(res, "/");
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
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
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
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
          }
          if (url === "/card/mode") {
            // Persistent NIGHTLY ↔ IMMEDIATE toggle (written to _goal.md). The
            // switch itself never executes anything — it only changes what a
            // future queue does. Run-now stays the explicit immediate trigger.
            const goalId = parseNbId(id);
            const mode = body.get("mode") === "immediate" ? "immediate" : "nightly";
            if (cfg.vaultDir && goalId) setProjectMode(cfg.vaultDir, goalId, mode);
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
          }
          if (url === "/nightly/toggle") {
            await setNightly(id, body.get("nightly") === "true");
            return redirectTo(res, `/project/${encodeURIComponent(id)}`);
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
          if (url === "/profiles/toggle") {
            const genre = body.get("genre") ?? "";
            if (genre) catalog.setEnabled(genre, body.get("enabled") === "true");
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

  return { server, store, catalog, intake, amend, doRewind, setNightly, bumpNightly, promote, deleteItem, runItem, kickRun };
}
