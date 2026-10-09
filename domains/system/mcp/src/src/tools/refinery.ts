/**
 * hwc_refinery — the refinement engine's Triage Surface Contract tool.
 *
 * READS the engine's markdown item store directly (one .md per Item, the
 * canonical Item JSON in a fenced ```json block — the same format
 * MarkdownItemStore round-trips) and stages items TRIAGED LIKE MAIL:
 *
 *   action — needs Eric: failed (a gate/run broke), parked (a decision
 *            unblocks it), or a hopper idea matured to stage=ready (promote).
 *   active — in-flight pipeline work (pending/running/passed on a real pipeline).
 *   hopper — raw untriaged ideas still captured/shaping (the idea backlog).
 *
 * This is a LOCAL FILE READ on hwc-server (the gateway and the refinery board
 * share the host) — the board at :8060 serves only HTML, but the .md store is
 * the source of truth. Same stageing as the morning briefing's
 * gather-refinery.mjs; keep the two in lockstep.
 *
 * WRITES are the generic workbench card_actions actions ({action, id}) proxied
 * to the board service's form-POST routes on loopback (the gateway and the
 * board share hwc-server): run → /run, park/resume → /status, delete →
 * /delete, intake → /intake, amend → /amend, stage → /stage, promote →
 * /promote. The board owns the state machine; this tool never edits item files.
 */

import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError } from "../errors.js";
import { loadNightlyEntries, nightlyReviewTools, type NightlyEntry } from "./nightly-review.js";

const ITEMS_DIR = process.env.REFINERY_ITEMS_DIR || "/var/lib/refinery/items";
const BOARD_URL = process.env.REFINERY_URL || "https://refinery.hwc.iheartwoodcraft.com";
/** The board service itself, for write proxying — loopback, same host. */
const BOARD_API = process.env.REFINERY_BOARD_URL || "http://127.0.0.1:8060";
const UNTRIAGED = "untriaged";

/** POST a form-encoded body to a board route. The board answers 303 See Other
 * on success (it's an HTML app); anything else is a failure. Writes must fail
 * loud — a workbench write must never fake success. */
async function boardPost(path: string, fields: Record<string, string>): Promise<void> {
  const res = await fetch(`${BOARD_API}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
    redirect: "manual", // the 303 IS the success signal; don't chase the HTML
  });
  if (res.status !== 303 && !res.ok) {
    throw new Error(`board ${path} answered ${res.status}`);
  }
}

/** The workbench card_actions vocabulary → board routes. Closed set: an
 * unknown verb is a validation error, not a silent no-op. */
const WRITE_VERBS: Record<string, (id: string) => Promise<void>> = {
  "run": (id) => boardPost("/run", { id }),
  "park": (id) => boardPost("/status", { id, status: "parked" }),
  "resume": (id) => boardPost("/status", { id, status: "pending" }),
  "delete": (id) => boardPost("/delete", { id }),
};

interface RefineryItem {
  id: string;
  pipeline?: string;
  step?: string;
  stage?: string;
  state?: string;
  parkedReason?: string;
  payload?: Record<string, unknown>;
  archived?: boolean;
  archivedAt?: string;
  history?: Array<{ step?: string; status?: string; at?: string; note?: string }>;
}

/* ── Merged triage board (action=triage): refinery items + nightly PRs ───────
 * The workbench host sends only {action, id[, target]} for a write or detail,
 * so a merged board names each card's owner in its id: `ref:<item id>` for a
 * refinery item, `pr:<review id>` for a nightly PR. Every verb, `detail`
 * included, routes on that prefix. Bare ids stay refinery ids (this tool's own
 * board and MCP callers use them); a nightly verb without `pr:` is rejected. */
const REF_PREFIX = "ref:";
const PR_PREFIX = "pr:";
/** Verbs owned by hwc_nightly_review; `rebuild` is its cardless board verb. */
const NIGHTLY_CARD_VERBS = new Set(["merge", "requeue"]);
const NIGHTLY_ROUTED = new Set(["detail", "merge", "requeue"]);
/** Done keeps only the newest N; its title carries the true count. */
const DONE_CAP = 10;

/** Nightly lanes → merged stage. */
const NIGHTLY_STAGE: Record<NightlyEntry["lane"], "needs-you" | "done"> = {
  "merge-ready": "needs-you",
  "needs-work": "needs-you",
  "reject-rec": "needs-you",
  dead: "needs-you",
  requeued: "done",
  merged: "done",
  rejected: "done",
  "already-merged": "done",
};

/** Same fenced-block extraction the engine's markdown-store uses — INCLUDING
 * its legacy-field migration (genre/phase/phaseStatus → pipeline/step-or-stage/
 * state). The engine migrates lazily on load, so untouched item files still
 * carry the old names; reading them raw made those items invisible here. */
function extractItem(md: string): RefineryItem | null {
  const m = md.match(/```json\n([\s\S]*?)\n```/);
  if (!m) return null;
  try {
    const raw = JSON.parse(m[1]) as Record<string, unknown>;
    if (!raw || typeof raw !== "object" || !raw["id"]) return null;
    if (raw["pipeline"] === undefined && raw["genre"] !== undefined) raw["pipeline"] = raw["genre"];
    if (raw["state"] === undefined && raw["phaseStatus"] !== undefined) raw["state"] = raw["phaseStatus"];
    if (raw["step"] === undefined && raw["stage"] === undefined && typeof raw["phase"] === "string") {
      if (raw["pipeline"] === UNTRIAGED) {
        raw["stage"] = ["captured", "shaping", "ready"].includes(raw["phase"]) ? raw["phase"] : "captured";
      } else {
        raw["step"] = raw["phase"];
      }
    }
    return raw as unknown as RefineryItem;
  } catch {
    return null;
  }
}

function titleOf(it: RefineryItem): string {
  const p = (it.payload && typeof it.payload === "object" ? it.payload : {}) as Record<string, unknown>;
  return String(p["title"] || p["input"] || it.id || "untitled").trim().slice(0, 140);
}

/** One human-meaningful status word (a ready hopper idea reads "ready to promote"). */
function labelOf(it: RefineryItem): string {
  if (it.state === "failed") return "failed";
  if (it.state === "parked") return "parked";
  if (it.pipeline === UNTRIAGED) return it.stage === "ready" ? "ready to promote" : it.stage || "idea";
  return it.state || "?";
}

type Stage = "action" | "active" | "hopper";

function stageOf(it: RefineryItem): Stage | null {
  if (it.archived === true) return null; // exit-ramped to /finished — off the working board
  // Untriaged FIRST: brain-sourced ideas carry state:"parked" by design
  // (parked-for-triage), so state-based stageing would misfile the whole
  // hopper as action items. Only a matured (ready) idea is an action.
  if (it.pipeline === UNTRIAGED) return it.stage === "ready" ? "action" : "hopper";
  if (it.state === "parked" || it.state === "failed") return "action";
  if (it.state === "pending" || it.state === "running" || it.state === "passed") return "active";
  return null;
}

/**
 * The board write actions an item's state allows — the card's `actions`. The board
 * accepts any status write, so this is where the legal set is decided: an
 * untriaged idea is promoted, not run; a parked item resumes; a running item
 * may only be parked; an archived item takes no card verb.
 */
function itemVerbs(it: RefineryItem): string[] {
  if (it.archived === true) return [];
  if (it.pipeline === UNTRIAGED) return ["delete"];
  switch (it.state) {
    case "parked": return ["resume", "delete"];
    case "running": return ["park"];
    case "failed":
    case "pending":
    case "passed": return ["run", "park", "delete"];
    default: return [];
  }
}

function toCard(it: RefineryItem, stage: Stage | "done") {
  const actions = itemVerbs(it);
  const status = labelOf(it);
  const pipeline = it.pipeline && it.pipeline !== UNTRIAGED ? it.pipeline : "";
  const where = [status, pipeline, it.step].filter(Boolean).join(" · ");
  const facts: [string, string][] = [];
  if (pipeline) facts.push(["pipeline", pipeline]);
  if (it.step) facts.push(["step", it.step]);
  if (it.pipeline === UNTRIAGED && it.stage) facts.push(["stage", it.stage]);
  if (it.state) facts.push(["state", it.state]);
  return {
    id: it.id,
    kind: "refinery",
    label: titleOf(it),
    priority: it.state === "failed" ? "critical" : stage === "hopper" ? "low" : "normal",
    // sender line = where it sits (mirrors crm_board's sender = source)
    sender: where,
    summary: it.parkedReason || "",
    url: `${BOARD_URL}/project/${encodeURIComponent(it.id)}`,
    actions,
    tag: it.pipeline === UNTRIAGED ? "idea" : "item",
    reason: it.parkedReason || where,
    facts,
  };
}

/** Authoritative time of an item's last change: archive time, else last history entry. */
function itemAt(it: RefineryItem): string {
  return it.archivedAt ?? it.history?.at(-1)?.at ?? "";
}

/** Route a workbench verb on a `pr:` card to hwc_nightly_review (prefix stripped). */
async function routeToNightly(action: string, args: Record<string, unknown>, id: string): Promise<ToolResult> {
  if (!NIGHTLY_ROUTED.has(action)) {
    return mcpError({
      type: "VALIDATION_ERROR",
      message: `${action} is not a nightly PR verb (pr: cards take detail, merge or requeue)`,
      context: { action, id: `${PR_PREFIX}${id}` },
    });
  }
  return nightlyReviewTools()[0].handler({ ...args, id });
}

async function loadItems(): Promise<RefineryItem[] | null> {
  try {
    const files = await readdir(ITEMS_DIR);
    const items: RefineryItem[] = [];
    for (const f of files) {
      if (!f.endsWith(".md")) continue;
      const raw = await readFile(join(ITEMS_DIR, f), "utf8").catch(() => "");
      const it = extractItem(raw);
      if (it) items.push(it);
    }
    return items;
  } catch {
    return null; // store dir unreadable — degrade to empty-but-flagged
  }
}

export function refineryTools(): ToolDef[] {
  return [
    {
      name: "hwc_refinery",
      description:
        "Refinement engine board, triaged like mail. Reads the engine's item store " +
        "(/var/lib/refinery/items) and stages items: action (failed / parked / ready-to-promote — " +
        "needs Eric), active (in-flight pipeline work), hopper (raw untriaged ideas; archived " +
        "items are excluded). action=board (default) returns the kanban; action=summary a " +
        "one-line rollup; action=detail (need id) the full item — history, parked reason, " +
        "gate verdicts — for tracking/resuming an item's progress. " +
        "Writes: intake (need text) captures a new idea into the hopper + brain backlog; " +
        "amend (need id+note) answers a parked item's asks and re-arms it; stage (need " +
        "id+target: captured|shaping|ready) matures an idea; promote (need id; optional " +
        "target=pipeline, default project-ideation) pushes a ready idea into refinement; " +
        "run / park / resume / delete (need id) as before. Column moves are rejected — " +
        "the board's stages are derived triage stages, not stored lanes. " +
        "action=triage merges this board with the nightly PR review into Needs you / Running / " +
        "Hopper / Done (newest 10); its card ids are ref:<item> or pr:<review>, and every verb " +
        "(detail included) routes on that prefix — pr: cards take merge/requeue/detail.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["board", "triage", "summary", "detail", "intake", "amend", "stage", "promote", "run", "park", "resume", "delete", "move", "merge", "requeue", "rebuild"],
            description:
              "board (default): kanban of action/active/hopper · triage: merged board with nightly PRs " +
              "(ids ref:/pr:) · summary: text rollup · detail: full item by id · " +
              "intake/amend/stage/promote/run/park/resume/delete: write actions · merge/requeue (pr: ids) " +
              "and rebuild route to hwc_nightly_review",
          },
          id: { type: "string", description: "Item id (detail + write actions)" },
          text: { type: "string", description: "intake: the idea sentence · amend: alias for note" },
          note: { type: "string", description: "amend: the answer/decision that unblocks the parked item" },
          target: {
            type: "string",
            description: "stage: captured|shaping|ready · promote: pipeline id (default project-ideation) · move: always rejected",
          },
        },
      },
      handler: async (input: Record<string, unknown>): Promise<ToolResult> => {
        const action = String(input["action"] ?? "board");
        let args = input;

        // ── merged-board routing: the id prefix names the owning tool ──────
        const rawId = String(input["id"] ?? "");
        if (rawId.startsWith(PR_PREFIX)) {
          return routeToNightly(action, input, rawId.slice(PR_PREFIX.length));
        }
        if (rawId.startsWith(REF_PREFIX)) {
          args = { ...input, id: rawId.slice(REF_PREFIX.length) };
        }
        if (NIGHTLY_CARD_VERBS.has(action)) {
          return mcpError({
            type: "VALIDATION_ERROR",
            message: `${action} needs a pr:<review id> (got ${rawId ? `"${rawId}"` : "no id"})`,
            suggestion: "Use the id from the triage board, or call hwc_nightly_review directly",
            context: { action, id: rawId },
          });
        }
        if (action === "rebuild") return nightlyReviewTools()[0].handler(input);

        // ── intake: capture a new idea (no id — the board mints one and also
        // appends it to the brain backlog) ─────────────────────────────────
        if (action === "intake") {
          const text = String(args["text"] ?? "").trim();
          if (!text) return mcpError({ type: "VALIDATION_ERROR", message: "intake: text is required" });
          try {
            await boardPost("/intake", { text });
          } catch (err) {
            return mcpError({ type: "NETWORK_ERROR", message: `refinery intake failed: ${err instanceof Error ? err.message : String(err)}` });
          }
          return { status: "ok", message: `refinery intake: "${text.slice(0, 80)}" — landed in the hopper (and the brain backlog)`, data: { url: BOARD_URL } };
        }

        // ── amend / stage / promote: the edit actions (board-owned state machine) ──
        if (action === "amend" || action === "stage" || action === "promote") {
          const id = String(args["id"] ?? "");
          if (!id) return mcpError({ type: "VALIDATION_ERROR", message: `${action}: id is required` });
          try {
            if (action === "amend") {
              const note = String(args["note"] ?? args["text"] ?? "").trim();
              if (!note) return mcpError({ type: "VALIDATION_ERROR", message: "amend: note is required" });
              await boardPost("/amend", { id, note });
            } else if (action === "stage") {
              const to = String(args["target"] ?? "");
              if (!["captured", "shaping", "ready"].includes(to)) {
                return mcpError({ type: "VALIDATION_ERROR", message: "stage: target must be captured|shaping|ready" });
              }
              await boardPost("/stage", { id, toStage: to });
            } else {
              await boardPost("/promote", { id, pipeline: String(args["target"] ?? "project-ideation") });
            }
          } catch (err) {
            return mcpError({ type: "NETWORK_ERROR", message: `refinery ${action} failed: ${err instanceof Error ? err.message : String(err)}` });
          }
          return { status: "ok", message: `refinery ${action}: ${id}`, data: { url: `${BOARD_URL}/project/${encodeURIComponent(id)}` } };
        }

        // ── detail: one item, in full — history + parked reason + verdicts ──
        if (action === "detail") {
          const id = String(args["id"] ?? "");
          if (!id) return mcpError({ type: "VALIDATION_ERROR", message: "detail: id is required" });
          const items = await loadItems();
          const it = (items ?? []).find((i) => i.id === id);
          if (!it) return mcpError({ type: "VALIDATION_ERROR", message: `no item "${id}" in the store` });
          return {
            status: "ok",
            message: `${it.id}: ${labelOf(it)}${it.pipeline && it.pipeline !== UNTRIAGED ? ` · ${it.pipeline} @ ${it.step ?? "?"}` : ""}`,
            data: { item: it, url: `${BOARD_URL}/project/${encodeURIComponent(it.id)}` },
          };
        }

        // ── writes: proxy the board's own POST routes ──────────────────────
        if (action in WRITE_VERBS || action === "move") {
          if (action === "move") {
            // H/L on the workbench board rides the generic move path, but these
            // stages are DERIVED (triage stages over state), not stored lanes.
            return mcpError({
              type: "VALIDATION_ERROR",
              message: "refinery stages are derived — use run/park/resume instead of a move",
            });
          }
          const id = String(args["id"] ?? "");
          if (!id) {
            return mcpError({ type: "VALIDATION_ERROR", message: `${action}: id is required` });
          }
          try {
            await WRITE_VERBS[action](id);
          } catch (err) {
            return mcpError({
              type: "NETWORK_ERROR",
              message: `refinery ${action} failed: ${err instanceof Error ? err.message : String(err)}`,
            });
          }
          return { status: "ok", message: `refinery ${action}: ${id}` };
        }

        const items = await loadItems();

        const itemsByStage: Record<Stage, RefineryItem[]> = { action: [], active: [], hopper: [] };
        for (const it of items ?? []) {
          const b = stageOf(it);
          if (b) itemsByStage[b].push(it);
        }
        // failed first, then parked, then ready-to-promote — most-actionable on top.
        const rank = (it: RefineryItem) => (it.state === "failed" ? 0 : it.state === "parked" ? 1 : 2);
        itemsByStage.action.sort((a, b) => rank(a) - rank(b));

        const counts = {
          action: itemsByStage.action.length,
          active: itemsByStage.active.length,
          hopper: itemsByStage.hopper.length,
        };
        const storeNote = items === null ? " (item store unreadable)" : "";

        if (action === "summary") {
          return {
            status: "ok",
            message: `Refinery: ${counts.action} action, ${counts.active} active, ${counts.hopper} hopper${storeNote}`,
            data: { counts, url: BOARD_URL },
            view: contract(
              "text",
              "Refinery",
              {
                greeting: `${counts.action} action · ${counts.active} active · ${counts.hopper} hopper`,
                summary: items === null ? "item store unreadable" : `${(items ?? []).length} items on the board`,
                highlights: itemsByStage.action.slice(0, 5).map((it) => `${labelOf(it)}: ${titleOf(it)}`),
              },
              { source: "hwc_refinery", url: BOARD_URL },
            ),
          };
        }

        if (action === "triage") {
          const nightly = await loadNightlyEntries();
          const ref = <T extends { id: string }>(card: T) => ({ ...card, id: `${REF_PREFIX}${card.id}` });
          const pr = <T extends { id: string }>(card: T) => ({ ...card, id: `${PR_PREFIX}${card.id}` });
          // Within a stage, PRs keep the nightly lane order (merge-ready first).
          const laneRank = (lane: NightlyEntry["lane"]) => Object.keys(NIGHTLY_STAGE).indexOf(lane);
          const nightlyIn = (stage: "needs-you" | "done") =>
            nightly.entries.filter((e) => NIGHTLY_STAGE[e.lane] === stage)
              .sort((a, b) => laneRank(a.lane) - laneRank(b.lane));
          // Done: archived refinery items + finished PRs, newest first by their
          // authoritative timestamp, then capped. Lanes keep load order, so sort here.
          const done = [
            ...(items ?? []).filter((it) => it.archived === true)
              .map((it) => ({ at: itemAt(it), card: ref(toCard(it, "done")) })),
            ...nightlyIn("done").map((e) => ({ at: e.at, card: pr(e.card) })),
          ].sort((a, b) => b.at.localeCompare(a.at));
          const stages = [
            {
              id: "needs-you",
              title: "Needs you",
              cards: [
                ...itemsByStage.action.map((it) => ref(toCard(it, "action"))),
                ...nightlyIn("needs-you").map((e) => pr(e.card)),
              ],
            },
            { id: "running", title: "Running", cards: itemsByStage.active.map((it) => ref(toCard(it, "active"))) },
            { id: "hopper", title: "Hopper", cards: itemsByStage.hopper.map((it) => ref(toCard(it, "hopper"))) },
            { id: "done", title: `Done (${done.length})`, cards: done.slice(0, DONE_CAP).map((d) => d.card) },
          ];
          const malformedNote = nightly.malformed > 0 ? ` (${nightly.malformed} malformed review(s) skipped)` : "";
          return {
            status: "ok",
            message: `Refinery triage: ${stages[0].cards.length} need you, ${counts.active} running, ` +
              `${counts.hopper} in the hopper, ${done.length} done${storeNote}${malformedNote}`,
            data: { counts: { ...counts, needsYou: stages[0].cards.length, done: done.length }, url: BOARD_URL },
            view: contract("kanban", "Refinery", { stages }, { source: "hwc_refinery", url: BOARD_URL }),
          };
        }

        // action === "board" (default)
        const stages = [
          { id: "action", title: "Action", cards: itemsByStage.action.map((it) => toCard(it, "action")) },
          { id: "active", title: "Active", cards: itemsByStage.active.map((it) => toCard(it, "active")) },
          { id: "hopper", title: "Hopper", cards: itemsByStage.hopper.map((it) => toCard(it, "hopper")) },
        ];

        return {
          status: "ok",
          message: `Refinery board: ${counts.action} action, ${counts.active} active, ${counts.hopper} hopper${storeNote}`,
          data: { counts, url: BOARD_URL },
          view: contract(
            "kanban",
            "Refinery",
            { stages },
            { source: "hwc_refinery", url: BOARD_URL, ...counts },
          ),
        };
      },
    },
  ];
}

/** Gatherer stage vocabulary. */
export function refineryStages<T = any>(section: unknown): Record<string, T[]> {
  const r = section && typeof section === "object" ? section as Record<string, unknown> : {};
  const groups = r.stages;
  return groups && typeof groups === "object" && !Array.isArray(groups) ? groups as Record<string, T[]> : {};
}
