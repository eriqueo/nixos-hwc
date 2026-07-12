/**
 * hwc_refinery — the refinement engine's Triage Surface Contract tool.
 *
 * READS the engine's markdown item store directly (one .md per Item, the
 * canonical Item JSON in a fenced ```json block — the same format
 * MarkdownItemStore round-trips) and buckets items TRIAGED LIKE MAIL:
 *
 *   action — needs Eric: failed (a gate/run broke), parked (a decision
 *            unblocks it), or a hopper idea matured to stage=ready (promote).
 *   active — in-flight pipeline work (pending/running/passed on a real pipeline).
 *   hopper — raw untriaged ideas still captured/shaping (the idea backlog).
 *
 * This is a LOCAL FILE READ on hwc-server (the gateway and the refinery board
 * share the host) — the board at :8060 serves only HTML, but the .md store is
 * the source of truth. Same bucketing as the morning briefing's
 * gather-refinery.mjs; keep the two in lockstep.
 *
 * WRITES are the generic workbench card_actions verbs ({action, id}) proxied
 * to the board service's form-POST routes on loopback (the gateway and the
 * board share hwc-server): run → /run, park/resume → /status, delete →
 * /delete. The board owns the state machine; this tool never edits item files.
 */

import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError } from "../errors.js";

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
}

/** Same fenced-block extraction the engine's markdown-store uses. */
function extractItem(md: string): RefineryItem | null {
  const m = md.match(/```json\n([\s\S]*?)\n```/);
  if (!m) return null;
  try {
    const it = JSON.parse(m[1]) as RefineryItem;
    return it && typeof it === "object" && it.id ? it : null;
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

type Bucket = "action" | "active" | "hopper";

function bucketOf(it: RefineryItem): Bucket | null {
  const untriaged = it.pipeline === UNTRIAGED;
  if (it.state === "parked" || it.state === "failed") return "action";
  if (untriaged && it.stage === "ready") return "action"; // matured idea awaiting promote
  if (untriaged) return "hopper";
  if (it.state === "pending" || it.state === "running" || it.state === "passed") return "active";
  return null;
}

function toCard(it: RefineryItem, bucket: Bucket) {
  const status = labelOf(it);
  const pipeline = it.pipeline && it.pipeline !== UNTRIAGED ? it.pipeline : "";
  return {
    id: it.id,
    kind: "refinery",
    label: titleOf(it),
    priority: it.state === "failed" ? "critical" : bucket === "hopper" ? "low" : "normal",
    // sender line = where it sits (mirrors crm_board's sender = source)
    sender: [status, pipeline, it.step].filter(Boolean).join(" · "),
    summary: it.parkedReason || "",
    url: `${BOARD_URL}/project/${encodeURIComponent(it.id)}`,
  };
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
        "(/var/lib/refinery/items) and buckets items: action (failed / parked / ready-to-promote — " +
        "needs Eric), active (in-flight pipeline work), hopper (raw untriaged ideas). " +
        "action=board (default) returns the kanban; action=summary a one-line rollup. " +
        "Writes (need id): run (run the item's pipeline now), park / resume (manual " +
        "state override), delete. Column moves are rejected — the board's columns are " +
        "derived triage buckets, not stored lanes.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["board", "summary", "run", "park", "resume", "delete", "move"],
            description:
              "board (default): kanban of action/active/hopper · summary: text rollup · " +
              "run/park/resume/delete: write verbs (need id)",
          },
          id: { type: "string", description: "Item id (write verbs)" },
          target: { type: "string", description: "move only (always rejected — derived columns)" },
        },
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        const action = String(args["action"] ?? "board");

        // ── writes: proxy the board's own POST routes ──────────────────────
        if (action in WRITE_VERBS || action === "move") {
          if (action === "move") {
            // H/L on the workbench board rides the generic move path, but these
            // columns are DERIVED (triage buckets over state), not stored lanes.
            return mcpError({
              type: "VALIDATION_ERROR",
              message: "refinery columns are derived — use run/park/resume instead of a move",
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

        const buckets: Record<Bucket, RefineryItem[]> = { action: [], active: [], hopper: [] };
        for (const it of items ?? []) {
          const b = bucketOf(it);
          if (b) buckets[b].push(it);
        }
        // failed first, then parked, then ready-to-promote — most-actionable on top.
        const rank = (it: RefineryItem) => (it.state === "failed" ? 0 : it.state === "parked" ? 1 : 2);
        buckets.action.sort((a, b) => rank(a) - rank(b));

        const counts = {
          action: buckets.action.length,
          active: buckets.active.length,
          hopper: buckets.hopper.length,
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
                highlights: buckets.action.slice(0, 5).map((it) => `${labelOf(it)}: ${titleOf(it)}`),
              },
              { source: "hwc_refinery", url: BOARD_URL },
            ),
          };
        }

        // action === "board" (default)
        const columns = [
          { id: "action", title: "Action", cards: buckets.action.map((it) => toCard(it, "action")) },
          { id: "active", title: "Active", cards: buckets.active.map((it) => toCard(it, "active")) },
          { id: "hopper", title: "Hopper", cards: buckets.hopper.map((it) => toCard(it, "hopper")) },
        ];

        return {
          status: "ok",
          message: `Refinery board: ${counts.action} action, ${counts.active} active, ${counts.hopper} hopper${storeNote}`,
          data: { counts, url: BOARD_URL },
          view: contract(
            "kanban",
            "Refinery",
            { columns },
            { source: "hwc_refinery", url: BOARD_URL, ...counts },
          ),
        };
      },
    },
  ];
}
