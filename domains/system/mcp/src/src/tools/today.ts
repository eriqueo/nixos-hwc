/**
 * hwc_today — the Today Queue: one ranked, actionable triage list over
 * everything the morning briefing already gathers.
 *
 * READS output/briefing.json (the merged artifact run.sh builds 3×/day) and
 * derives action_items from its sections — overdue invoices, overdue CalDAV
 * tasks, stale leads, the refinery action bucket, finished nightly builds,
 * system alerts, urgent mail. No new collection: the briefing pipeline stays
 * the single gatherer; this tool is triage + verbs.
 *
 * Every item carries a stable id (`<source>:<entity>`), a one-line `why`, an
 * effort estimate, a severity, and its verb set. Ranking: red before amber,
 * then oldest first. The queue caps at TOP_N with a spillover count — the
 * point is "do these today", not another unbounded list.
 *
 * WRITES (Triage Surface Contract verbs, {action, id}):
 *   dismiss  — snooze the item's case: optional `reason` recorded; wakes if a
 *              system: item resurfaces WORSE than at dismissal, else on the
 *              30-day expiry (TTL is the fallback, not the mechanism).
 *   complete — task items only: delegated to hwc_tasks_update (CalDAV);
 *              resolves the case (reopens if the item survives a NEWER gather
 *              — the completion demonstrably didn't take).
 *   agent    — queue a PRE-WRITTEN prompt card (interpolated from
 *              prompts/today/<source>.txt at gather time — Eric reads exactly
 *              what will run before he taps) into output/dispatch/. A systemd
 *              path unit runs it read-only; the report lands in
 *              output/reports/ and the item links it on the next read.
 *
 * READS also include action=delta: what changed since the last briefing run
 * (new / reopened / worsened / resolved case ids with one-line summaries) so
 * the brief can say what CHANGED, not restate state.
 *
 * State is a case ledger (engineering-principles Principle 21; spec in brain
 * _library/ai-ml/case_ledger_pattern.md) in output/today-state.json beside
 * briefing.json — same eric-owned dir. v2 schema {schemaVersion, cases}; v1
 * {dismissed, dispatched} files migrate transparently on read (today-ledger's
 * migrateState). The pure state machine lives in today-ledger.ts; this file
 * owns all I/O and is the single writer of the state file.
 */

import { readFile, writeFile, rename, mkdir, access } from "node:fs/promises";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError, catchError } from "../errors.js";
import { tasksTools } from "./tasks.js";
import {
  migrateState,
  reconcile,
  bumpSurfaced,
  snoozeCase,
  resolveCase,
  recordAction,
  computeDelta,
  type LedgerState,
  type ObservedItem,
} from "./today-ledger.js";

const BRIEFING_DIR =
  process.env.HWC_BRIEFING_DIR ||
  "/home/eric/.nixos/domains/business/morning-briefing";
const BRIEFING_PATH = join(BRIEFING_DIR, "output", "briefing.json");
const STATE_PATH = join(BRIEFING_DIR, "output", "today-state.json");
const DISPATCH_DIR = join(BRIEFING_DIR, "output", "dispatch");
const REPORTS_DIR = join(BRIEFING_DIR, "output", "reports");
const TEMPLATE_DIR = join(BRIEFING_DIR, "prompts", "today");

const TOP_N = 7;
const STALE_LEAD_DAYS = 14;
const DAY_MS = 86_400_000;

type Severity = "red" | "amber";
type Verb = "dismiss" | "complete" | "agent";

interface TodayItem {
  id: string;
  source: "invoice" | "task" | "lead" | "refinery" | "nightly" | "system" | "mail";
  title: string;
  /** One line: what it costs to ignore. */
  why: string;
  severity: Severity;
  effort_min: number;
  age_days: number;
  url: string | null;
  verbs: Verb[];
  /** Present once an agent verb has run and its report exists. */
  report: string | null;
}

/* ── state (case ledger — pure machine in today-ledger.ts) ────────── */

async function loadState(now: Date): Promise<LedgerState> {
  let raw: unknown = null;
  try {
    raw = JSON.parse(await readFile(STATE_PATH, "utf8"));
  } catch {
    /* first run or unreadable → empty ledger */
  }
  return migrateState(raw, now);
}

/** Atomic per the briefing pipeline's .tmp → mv idiom. */
async function saveState(state: LedgerState): Promise<void> {
  const tmp = STATE_PATH + ".tmp";
  await writeFile(tmp, JSON.stringify(state, null, 2));
  await rename(tmp, STATE_PATH);
}

/* ── derivation from briefing.json ────────────────────────────────── */

function daysAgo(iso: string | undefined | null): number {
  if (!iso) return 0;
  const t = new Date(iso).getTime();
  return Number.isFinite(t) ? Math.max(0, Math.floor((Date.now() - t) / 86400_000)) : 0;
}

/** Stable, filename-safe id fragment. */
function slug(s: string): string {
  return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 60);
}

// Effort defaults per source — data, not judgment calls scattered in code.
const EFFORT: Record<TodayItem["source"], number> = {
  invoice: 15, task: 10, lead: 10, refinery: 10, nightly: 15, system: 5, mail: 5,
};

function deriveItems(b: Record<string, any>): TodayItem[] {
  const s = b.sections ?? {};
  const items: TodayItem[] = [];

  for (const inv of s.overdue?.items ?? []) {
    const days = Number(inv.days_past_due ?? daysAgo(inv.due_date));
    items.push({
      id: `invoice:${slug(`${inv.job_number ?? ""}-${inv.name ?? "unknown"}`)}`,
      source: "invoice",
      title: `${String(inv.name ?? "Overdue invoice")} — ${String(inv.job_name ?? inv.account ?? "")}`,
      why: `$${Number(inv.amount ?? 0).toLocaleString()} outstanding · ${days}d past due`,
      severity: "red",
      effort_min: EFFORT.invoice,
      age_days: days,
      url: inv.url ?? null,
      verbs: ["dismiss"],
      report: null,
    });
  }

  for (const t of s.tasks?.overdue ?? []) {
    const days = daysAgo(t.due_date ?? t.due);
    // uid comes from gather-live.mjs; without it the complete verb can't
    // address CalDAV, so the item degrades to dismiss-only.
    const uid = t.uid ? String(t.uid) : null;
    items.push({
      id: uid ? `task:${uid}` : `task:${slug(String(t.name ?? t.summary ?? "task"))}`,
      source: "task",
      title: String(t.name ?? t.summary ?? "Overdue task"),
      why: `${days}d overdue${t.list ? ` · ${t.list}` : ""}`,
      severity: days > 7 ? "red" : "amber",
      effort_min: EFFORT.task,
      age_days: days,
      url: null,
      verbs: uid ? ["complete", "dismiss"] : ["dismiss"],
      report: null,
    });
  }

  for (const l of s.leads?.items ?? []) {
    const days = Number(l.days_old ?? 0);
    if (days < STALE_LEAD_DAYS) continue; // fresh leads are pipeline, not triage
    items.push({
      id: `lead:${slug(String(l.job_number ?? l.name ?? "lead"))}`,
      source: "lead",
      title: `Stale lead: ${String(l.name ?? "unknown")}`,
      why: `${days}d in "1. Contacted" — follow up or mark Closed Lost`,
      severity: days > 30 ? "red" : "amber",
      effort_min: EFFORT.lead,
      age_days: days,
      url: l.url ?? null,
      verbs: ["dismiss"],
      report: null,
    });
  }

  for (const r of s.refinery?.buckets?.action ?? []) {
    const failed = r.state === "failed";
    items.push({
      id: `refinery:${String(r.id)}`,
      source: "refinery",
      title: `${r.label ?? r.state}: ${String(r.title ?? r.id)}`,
      why: failed
        ? "a gate broke — the pipeline is stopped until this is fixed"
        : r.state === "parked"
          ? `parked: ${String(r.reason ?? "a decision unblocks it")}`.slice(0, 120)
          : "shaped and ready — promote it or park it",
      severity: failed ? "red" : "amber",
      effort_min: EFFORT.refinery,
      age_days: 0, // the item store carries no timestamps in its card form
      url: r.url ?? null,
      verbs: ["agent", "dismiss"],
      report: null,
    });
  }

  for (const nb of s.ops?.nightly_builds_finished ?? []) {
    const name = String(nb);
    items.push({
      id: `nightly:${slug(name)}`,
      source: "nightly",
      title: `Review overnight build: ${name}`,
      why: "an autonomous branch is waiting on your merge/re-queue call",
      severity: "amber",
      effort_min: EFFORT.nightly,
      age_days: 0,
      url: null,
      verbs: ["dismiss"],
      report: null,
    });
  }

  for (const a of b.alerts ?? []) {
    if (a.level !== "critical" && a.level !== "warning") continue;
    if (a.section === "refinery") continue; // itemized above, don't double-count
    // Strip numbers before slugging: "Grafana (89%)" and "Grafana (63%)" are
    // the same underlying problem — a fluctuating figure must not mint a new
    // id every run or dismissals never stick.
    items.push({
      id: `system:${slug(String(a.message ?? a.section ?? "alert").replace(/[\d.,%]+/g, ""))}`,
      source: "system",
      title: String(a.message ?? "System alert"),
      why: a.level === "critical" ? "critical — something is down right now" : "recurring warning — worth a look",
      severity: a.level === "critical" ? "red" : "amber",
      effort_min: EFFORT.system,
      age_days: 0,
      url: a.url ?? null,
      verbs: ["agent", "dismiss"],
      report: null,
    });
  }

  for (const m of b.mail_triage?.buckets?.urgent ?? []) {
    items.push({
      id: `mail:${String(m.thread_id ?? slug(String(m.subject ?? "mail")))}`,
      source: "mail",
      title: `Mail: ${String(m.subject ?? "urgent thread")}`,
      why: String(m.summary ?? "triaged urgent").slice(0, 120),
      severity: "amber",
      effort_min: EFFORT.mail,
      age_days: 0,
      url: null,
      verbs: ["dismiss"],
      report: null,
    });
  }

  return items;
}

/* ── agent dispatch: pre-written prompt cards ─────────────────────── */

async function fileExists(p: string): Promise<boolean> {
  try { await access(p); return true; } catch { return false; }
}

/** Interpolate {{VAR}} placeholders; unknown vars stay literal (loud, greppable). */
function interpolate(tpl: string, vars: Record<string, string>): string {
  return tpl.replace(/\{\{(\w+)\}\}/g, (m, k) => (k in vars ? vars[k] : m));
}

async function queueDispatch(item: TodayItem): Promise<string> {
  const tplPath = join(TEMPLATE_DIR, `${item.source}.txt`);
  const fallback = join(TEMPLATE_DIR, "generic.txt");
  const tpl = await readFile((await fileExists(tplPath)) ? tplPath : fallback, "utf8");
  const prompt = interpolate(tpl, {
    ID: item.id,
    TITLE: item.title,
    WHY: item.why,
    URL: item.url ?? "",
    SOURCE: item.source,
  });
  await mkdir(DISPATCH_DIR, { recursive: true });
  const cardPath = join(DISPATCH_DIR, `${slug(item.id)}.md`);
  const card = [
    `<!-- today-dispatch card · id: ${item.id} · queued: ${new Date().toISOString()} -->`,
    `<!-- REPORT_PATH: ${join(REPORTS_DIR, `${slug(item.id)}.md`)} -->`,
    "",
    prompt,
    "",
  ].join("\n");
  await writeFile(cardPath, card);
  return cardPath;
}

async function reportFor(item: TodayItem): Promise<string | null> {
  const p = join(REPORTS_DIR, `${slug(item.id)}.md`);
  // served via the dashboard's reports/ symlink — relative URL for the SPA
  return (await fileExists(p)) ? `reports/${slug(item.id)}.md` : null;
}

/* ── ranking ──────────────────────────────────────────────────────── */

function rank(a: TodayItem, b: TodayItem): number {
  if (a.severity !== b.severity) return a.severity === "red" ? -1 : 1;
  if (a.age_days !== b.age_days) return b.age_days - a.age_days;
  return a.effort_min - b.effort_min;
}

/* ── tool ─────────────────────────────────────────────────────────── */

async function completeTask(uid: string): Promise<ToolResult> {
  const update = tasksTools().find((t) => t.name === "hwc_tasks_update");
  if (!update) return mcpError({ type: "INTERNAL_ERROR", message: "hwc_tasks_update not found" });
  return update.handler({ uid, action: "complete" });
}

export function todayTools(): ToolDef[] {
  return [
    {
      name: "hwc_today",
      description:
        "The Today Queue — one ranked, actionable triage list derived from the morning " +
        "briefing's sections: overdue invoices, overdue tasks, stale leads, refinery items " +
        "needing a decision, finished nightly builds, system alerts, urgent mail. " +
        `action=board (default) returns the top ${TOP_N} with a spillover count; ` +
        "action=summary a one-line rollup; action=delta what changed since the last " +
        "run (new/reopened/worsened/resolved cases). Writes (need id): dismiss " +
        "(snooze the case — optional reason; wakes if a system item resurfaces worse, " +
        "else on 30d expiry), complete (task items — CalDAV), agent (queue the item's " +
        "pre-written read-only diagnosis prompt for the dispatch runner).",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["board", "summary", "delta", "dismiss", "complete", "agent"],
            description:
              `board (default): ranked top ${TOP_N} · summary: text rollup · ` +
              "delta: changes since last run · dismiss/complete/agent: write verbs (need id)",
          },
          id: { type: "string", description: "Item id (write verbs), e.g. task:<uid>" },
          reason: {
            type: "string",
            description: "dismiss only: why — recorded on the case for later runs",
          },
          since: {
            type: "string",
            description:
              "delta only: ISO cutoff. Omitted → since the previous parameterless " +
              "delta call (the briefing runs advance this cursor).",
          },
        },
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        const action = String(args["action"] ?? "board");
        const now = new Date();

        let briefing: Record<string, any>;
        try {
          briefing = JSON.parse(await readFile(BRIEFING_PATH, "utf8"));
        } catch (err) {
          return catchError("NOT_FOUND", "briefing.json unreadable — has the briefing run?", err);
        }

        const state = await loadState(now);
        const all = deriveItems(briefing);

        // Lifecycle pass: fold this render's observations into the ledger.
        // observedAt gates reopen-after-resolution (a completed item lingering
        // in the SAME briefing must not reopen); sweepAbsent guards a degraded
        // briefing (error marker / empty) from mass-resolving open cases.
        const genMs = Date.parse(String(briefing.generated_at ?? ""));
        const observed: ObservedItem[] = all.map((i) => ({
          id: i.id,
          title: i.title,
          severity: i.severity,
          source: i.source,
        }));
        const visibleIds = reconcile(state, observed, now, {
          ...(Number.isFinite(genMs) ? { observedAt: new Date(genMs) } : {}),
          sweepAbsent: all.length > 0 && !briefing.error,
        });

        // ── writes ─────────────────────────────────────────────────
        if (action === "dismiss" || action === "complete" || action === "agent") {
          const id = String(args["id"] ?? "");
          if (!id) return mcpError({ type: "VALIDATION_ERROR", message: `${action}: id is required` });
          const item = all.find((i) => i.id === id);

          if (action === "dismiss") {
            snoozeCase(
              state,
              id,
              {
                ...(args["reason"] !== undefined ? { reason: String(args["reason"]) } : {}),
                ...(item ? { severityAtSnooze: item.severity, title: item.title } : {}),
              },
              now,
            );
            await saveState(state);
            return { status: "ok", message: `dismissed: ${id}` };
          }

          if (!item) {
            return mcpError({
              type: "NOT_FOUND",
              message: `no live item ${id}`,
              suggestion: "It may have cleared on the last briefing run — read the board first.",
            });
          }

          if (action === "complete") {
            if (item.source !== "task") {
              return mcpError({
                type: "VALIDATION_ERROR",
                message: "complete is only valid for task: items",
                suggestion: "Use the item's deep link, or dismiss it.",
              });
            }
            const res = await completeTask(id.slice("task:".length));
            if (res.status === "ok") {
              // Resolve the case immediately — don't wait for re-gather. If the
              // item survives a NEWER briefing, reconcile reopens it (the
              // completion demonstrably didn't take).
              resolveCase(state, id, "completed via CalDAV (hwc_tasks_update)", now);
              await saveState(state);
            }
            return res;
          }

          // action === "agent"
          try {
            const cardPath = await queueDispatch(item);
            recordAction(state, id, `agent dispatch queued (card ${cardPath})`, now);
            await saveState(state);
            return {
              status: "ok",
              message: `queued for dispatch: ${id}`,
              data: { card: cardPath },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", `agent dispatch failed for ${id}`, err);
          }
        }

        // ── delta: what changed since the last run ─────────────────
        if (action === "delta") {
          const sinceArg = args["since"] !== undefined ? String(args["since"]) : undefined;
          if (sinceArg !== undefined && !Number.isFinite(Date.parse(sinceArg))) {
            return mcpError({ type: "VALIDATION_ERROR", message: `delta: unparsable since "${sinceArg}"` });
          }
          const sinceMs = sinceArg !== undefined
            ? Date.parse(sinceArg)
            : state.lastDeltaAt !== undefined && Number.isFinite(Date.parse(state.lastDeltaAt))
              ? Date.parse(state.lastDeltaAt)
              : now.getTime() - DAY_MS;
          const delta = computeDelta(state, new Date(sinceMs));
          if (sinceArg === undefined) state.lastDeltaAt = now.toISOString(); // advance the cursor
          await saveState(state); // persists reconcile results + cursor
          const counts =
            `${delta.new.length} new · ${delta.reopened.length} reopened · ` +
            `${delta.worsened.length} worsened · ${delta.resolved.length} resolved`;
          return {
            status: "ok",
            message: `Changed since ${delta.since}: ${counts}`,
            data: delta,
          };
        }

        // ── reads ──────────────────────────────────────────────────
        const live = all.filter((i) => visibleIds.has(i.id));
        for (const i of live) i.report = await reportFor(i);
        live.sort(rank);
        // Every red makes the queue — a red squeezed out by the cap is an
        // invisible emergency. The cap only limits how many ambers pad it out.
        const reds = live.filter((i) => i.severity === "red");
        const queue = reds.length >= TOP_N
          ? reds
          : live.slice(0, TOP_N);
        const spillover = live.length - queue.length;
        const generatedAt = String(briefing.generated_at ?? "");

        // This render surfaced the queue's items: counter always, observation
        // event bounded to one per case per day. Persisting here also lands
        // the reconcile pass (reopens/resolves) from this read.
        bumpSurfaced(state, queue.map((i) => i.id), now);
        await saveState(state);

        if (action === "summary") {
          const reds = queue.filter((i) => i.severity === "red").length;
          return {
            status: "ok",
            message: `Today: ${queue.length} item(s) (${reds} red)${spillover > 0 ? `, +${spillover} more` : ""}`,
            data: { count: queue.length, red: reds, spillover, generated_at: generatedAt },
            view: contract(
              "text",
              "Today",
              {
                greeting: `${queue.length} for today · ${reds} red${spillover > 0 ? ` · +${spillover} waiting` : ""}`,
                summary: `from briefing ${generatedAt}`,
                highlights: queue.slice(0, 5).map((i) => `[${i.severity}] ${i.title} — ${i.why}`),
              },
              { source: "hwc_today" },
            ),
          };
        }

        // action === "board" (default) — a list, not a kanban: it's a queue.
        return {
          status: "ok",
          message: `Today queue: ${queue.length} item(s)${spillover > 0 ? `, +${spillover} spillover` : ""}`,
          data: { items: queue, spillover, generated_at: generatedAt },
          view: contract(
            "list",
            "Today",
            {
              items: queue.map((i) => ({
                id: i.id,
                kind: "today",
                label: i.title,
                priority: i.severity === "red" ? "critical" : "normal",
                sender: `${i.source} · ~${i.effort_min} min${i.age_days ? ` · ${i.age_days}d` : ""}`,
                summary: i.why + (i.report ? ` · report ready` : ""),
                url: i.url,
                verbs: i.verbs,
              })),
            },
            { source: "hwc_today", spillover, generated_at: generatedAt },
          ),
        };
      },
    },
  ];
}
