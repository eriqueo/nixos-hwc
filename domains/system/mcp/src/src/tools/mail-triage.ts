/**
 * hwc_mail_triage — the mail domain's Triage Surface Contract tool.
 *
 * READS (board/summary) come from the CACHED mail-triage produced daily by
 * domains/business/morning-briefing (run.sh injects a `.mail_triage` key into
 * output/briefing.json), re-bucketed by the LIVE notmuch attention/* tags so
 * moves persist, and filtered to threads still in the inbox.
 *
 * WRITES are the generic workbench card_actions verbs ({action, id[,target]}):
 * triage-<bucket> / move (replace the attention/* tag set), archive, trash,
 * mark-read, flag-action — all plain notmuch tag ops on `thread:<id>`, the same store
 * aerc and the briefing read. Never runs Claude.
 *
 * Path is late-bound from env HWC_BRIEFING_JSON, defaulting to the real
 * pipeline output path. Missing/unparseable file or failed live search → coded read failure; writes fail loud (a workbench write must never fake success).
 */

import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError } from "../errors.js";
import { TRIAGE_BUCKETS, triageTag, mailTagActions } from "./mail.js";

/** Default briefing output path (run.sh writes here, then injects .mail_triage). */
const DEFAULT_BRIEFING_JSON =
  "/home/eric/.nixos/domains/business/morning-briefing/output/briefing.json";

/** A single classified thread as produced by the local Laya runner. */
interface TriageThread {
  thread_id: string;
  subject: string;
  sender?: string;
  from_name?: string;
  from_address?: string;
  date_relative?: string;
  tags: string[];
  has_attachment?: boolean;
  summary?: string;
  suggested_action?: string;
  urgency_reason?: string;
}

interface MailTriage {
  generated_at: string;
  query_window_hours?: number;
  total_unread?: number;
  buckets: {
    act: TriageThread[];
    look: TriageThread[];
    bulk: TriageThread[];
    junk: TriageThread[];
  };
  stats: {
    act_count: number;
    look_count: number;
    bulk_count: number;
    junk_count: number;
  };
}

type Bucket = "act" | "look" | "bulk" | "junk";

const PRIORITY: Record<Bucket, "critical" | "normal" | "low"> = {
  act: "critical",
  look: "normal",
  bulk: "low",
  junk: "low",
};

/** Read + JSON-parse the briefing file and pull .mail_triage. null on any failure. */
async function loadTriage(path: string): Promise<MailTriage | null> {
  try {
    const raw = await readFile(path, "utf-8");
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    const triage = parsed?.mail_triage as MailTriage | undefined;
    if (!triage || typeof triage !== "object") return null;
    return triage;
  } catch {
    return null;
  }
}

/** Defensive accessor: always returns an array of threads for a bucket. */
function bucketThreads(triage: MailTriage | null, bucket: Bucket): TriageThread[] {
  const arr = triage?.buckets?.[bucket];
  return Array.isArray(arr) ? arr : [];
}

const NOTMUCH_CANDIDATES = ["notmuch", "/etc/profiles/per-user/eric/bin/notmuch"];

type Inbox = Map<string, Set<string>>;

/** One scan, bounded at 3.5s/2MiB; never fan out per bucket under the gateway CPU quota. */
function notmuchInbox(ids: readonly string[]): Promise<Inbox> {
  return new Promise((resolve, reject) => {
    const tryBin = (i: number): void => {
      if (i >= NOTMUCH_CANDIDATES.length) {
        reject(new Error("notmuch binary not found"));
        return;
      }
      execFile(
        NOTMUCH_CANDIDATES[i],
        ["search", "--format=json", "--output=summary",
          `(tag:inbox OR tag:later OR tag:trash) AND (${ids.map(id => `thread:${id}`).join(" OR ")})`],
        { timeout: 3500, maxBuffer: 2 * 1024 * 1024 },
        (err, stdout) => {
          if (err && (err as NodeJS.ErrnoException).code === "ENOENT") {
            tryBin(i + 1);
            return;
          }
          if (err) {
            reject(err);
            return;
          }
          try {
            const rows: unknown = JSON.parse(stdout);
            if (!Array.isArray(rows)) throw Error("Invalid notmuch summary");
            const inbox: Inbox = new Map();
            for (const row of rows) {
              if (!row || typeof row.thread !== "string" || !Array.isArray(row.tags)
                  || !row.tags.every((tag: unknown) => typeof tag === "string")) {
                throw Error("Invalid notmuch thread/tags");
              }
              inbox.set(row.thread, new Set(row.tags));
            }
            resolve(inbox);
          } catch (error) { reject(error); }
        },
      );
    };
    tryBin(0);
  });
}

/**
 * Re-bucket the cached triage by the LIVE notmuch `attention/<state>` tags so a
 * workbench move survives a refresh
 * WITHOUT re-running the daily briefing. The briefing remains the content
 * source (subject/summary/sender); the tag is the source of truth for
 * PLACEMENT. A thread carrying no attention/* tag keeps its cached
 * bucket. Threads no longer in the inbox (archived/trashed since the cache
 * was written — including via this tool's own verbs) are dropped, so an
 * archive durably removes the card instead of resurrecting on refresh.
 * notmuch unavailable → coded failure; a successful empty inbox empties the board.
 */
export async function reflectLiveBuckets(
  cached: Record<Bucket, TriageThread[]>,
  readInbox: (ids: readonly string[]) => Promise<Inbox> = notmuchInbox,
  _unreadOnly = false,
): Promise<Record<Bucket, TriageThread[]>> {
  // Only cached threads can appear on this surface. Scanning the entire inbox
  // starves khal under the gateway CPU quota. Bound argv/query work at 512 IDs;
  // overflow or invalid cache identity fails visibly, never falls back to all mail.
  const ids = [...new Set(TRIAGE_BUCKETS.flatMap(bucket =>
    cached[bucket as Bucket].map(thread => thread.thread_id)))];
  if (ids.length > 512 || ids.some(id => typeof id !== "string" || !/^[0-9a-f]{1,64}$/.test(id))) {
    throw Error("Mail triage requires at most 512 valid hexadecimal thread IDs");
  }
  if (ids.length === 0) return {act: [], look: [], bulk: [], junk: []};
  const inbox = await readInbox(ids);
  const seen = new Set<string>();
  const out: Record<Bucket, TriageThread[]> = { act: [], look: [], bulk: [], junk: [] };
  for (const bucket of TRIAGE_BUCKETS) {
    for (const thread of cached[bucket as Bucket]) {
      const tags = inbox.get(thread.thread_id);
      if (!tags || seen.has(thread.thread_id)) continue;
      seen.add(thread.thread_id);
      // Keep the established last-bucket precedence if a thread has multiple tags.
      const live = [...TRIAGE_BUCKETS].reverse().find(b => tags.has(triageTag(b))) as Bucket | undefined;
      out[live ?? (bucket as Bucket)].push(thread);
    }
  }
  return out;
}

/* ─── Write verbs (generic workbench card_actions path) ──────────────────── */

/** Tag ops per verb. triage-<bucket> and move replace the attention/* set. */
function verbTagOps(verb: string, target?: string): string[] | null {
  const bucketOf = (b: string): string[] | null =>
    (TRIAGE_BUCKETS as readonly string[]).includes(b)
      ? [
          ...TRIAGE_BUCKETS.filter((o) => o !== b).map((o) => `-${triageTag(o)}`),
          `+${triageTag(b)}`,
        ]
      : null;
  if (verb === "move") return target ? bucketOf(target) : null;
  if (verb.startsWith("triage-")) return bucketOf(verb.slice("triage-".length));
  if (verb === "archive" || verb === "trash") return mailTagActions()[verb];
  if (verb === "mark-read") return mailTagActions().read;
  if (verb === "flag-action") return ["+action"];
  return null;
}

const WRITE_VERBS = ["move", "archive", "trash", "mark-read", "flag-action", "retriage"] as const;

/** Apply tag ops to thread:<id>. Resolves an error string or null on success. */
function notmuchTagThread(id: string, ops: string[]): Promise<string | null> {
  return new Promise((resolve) => {
    const tryBin = (i: number): void => {
      if (i >= NOTMUCH_CANDIDATES.length) {
        resolve("notmuch binary not found");
        return;
      }
      execFile(
        NOTMUCH_CANDIDATES[i],
        ["tag", ...ops, "--", `thread:${id}`],
        { timeout: 10_000 },
        (err, _stdout, stderr) => {
          if (err && (err as NodeJS.ErrnoException).code === "ENOENT") {
            tryBin(i + 1);
            return;
          }
          resolve(err ? (stderr || String(err)).slice(0, 300) : null);
        },
      );
    };
    tryBin(0);
  });
}

/** Map a thread to a kanban card. */
function toCard(thread: TriageThread, bucket: Bucket) {
  return {
    id: thread.thread_id,
    kind: "mail",
    label: thread.subject,
    priority: PRIORITY[bucket],
    sender: thread.sender ?? thread.from_name ?? thread.from_address ?? "?",
    summary: thread.summary,
    suggested_action: thread.suggested_action,
    urgency_reason: thread.urgency_reason,
    date: thread.date_relative,
  };
}

/** HH:MM (local) extracted from an ISO8601 generated_at, or "unknown". */
function clockFromIso(iso: string | undefined): string {
  if (!iso) return "unknown";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "unknown";
  return d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function mailTriageTools(
  briefingPath = process.env.HWC_BRIEFING_JSON || DEFAULT_BRIEFING_JSON,
  readInbox: (ids: readonly string[]) => Promise<Inbox> = notmuchInbox,
): ToolDef[] {

  return [
    {
      name: "hwc_mail_triage",
      description:
        "Mail triage board (Triage Surface Contract). READS: action=board (default) returns a kanban of " +
        "Act/Look/Bulk/Junk columns from the cached Laya classification, reflected from live " +
        "notmuch attention/* tags; action=summary returns a compact overview; action=digest returns " +
        "up to eight Act/Look threads. Writes hit the same notmuch tags aerc and the briefing read.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: [
              "board", "summary", "digest",
              ...TRIAGE_BUCKETS.map((b) => `triage-${b}`),
              ...WRITE_VERBS,
            ],
            default: "board",
            description:
              "board/summary/digest = reads; triage-<bucket>, move (+target), archive, trash, mark-read, flag-action = per-thread writes (require id)",
          },
          id: {
            type: "string",
            description: "[writes] notmuch thread id (hex, no 'thread:' prefix) — the kanban card id",
          },
          target: {
            type: "string",
            enum: [...TRIAGE_BUCKETS],
            description: "[move] destination bucket (the kanban column id)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        const action = (args.action as string) || "board";

        // ── retriage: cardless board verb — fire-and-forget ─────────────────
        // Touch the trigger file; the mail-retriage systemd path unit starts
        // triage-mail.sh `delta` (classify + tag + merge, ~1-2 min). This
        // keeps the LLM run out of the gateway's process/sandbox entirely.
        if (action === "retriage") {
          const trigger = process.env.HWC_RETRIAGE_TRIGGER;
          if (!trigger) {
            return mcpError({
              type: "UNAVAILABLE",
              message: "HWC_RETRIAGE_TRIGGER is not set — retriage trigger unavailable",
              suggestion: "Deploy the morning-briefing module's mail-retriage units (unified-triage Phase 4)",
            });
          }
          try {
            await writeFile(trigger, `${new Date().toISOString()}\n`);
          } catch (err) {
            return mcpError({
              type: "COMMAND_FAILED",
              message: `could not touch retriage trigger ${trigger}`,
              error: String(err).slice(0, 300),
            });
          }
          return {
            status: "ok",
            message:
              "retriage requested — mail-retriage.service will classify unclassified unread threads (~1-2 min); refresh the board to see them",
            data: { action: "retriage", trigger },
          };
        }

        // ── writes: {action, id[, target]} — the generic card_actions path ──
        if (action !== "board" && action !== "summary" && action !== "digest") {
          const id = String(args.id ?? "").replace(/^thread:/, "").trim();
          if (!/^[0-9a-f]+$/i.test(id)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `write '${action}' needs a notmuch thread id (hex), got ${JSON.stringify(args.id ?? null)}`,
              suggestion: "Pass the kanban card id as `id`",
            });
          }
          const ops = verbTagOps(action, args.target as string | undefined);
          if (ops === null) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `unknown verb or missing/invalid target for '${action}'`,
              suggestion: `Verbs: ${TRIAGE_BUCKETS.map((b) => `triage-${b}`).join(", ")}, move (target=${TRIAGE_BUCKETS.join("|")}), archive, trash, mark-read, flag-action`,
            });
          }
          const err = await notmuchTagThread(id, ops);
          if (err !== null) {
            return mcpError({
              type: "COMMAND_FAILED",
              message: `notmuch tag failed for thread:${id}`,
              error: err,
            });
          }
          return {
            status: "ok",
            message: `${action} → thread:${id} (${ops.join(" ")})`,
            data: { action, id, ops },
          };
        }

        // ── reads ──
        const triage = await loadTriage(briefingPath);

        if (!triage) return mcpError({ type: "UNAVAILABLE", message: "Mail digest is unavailable. Open aerc or run mail triage." });
        // Reflect any persisted moves: re-bucket cached threads by their live
        // attention/* notmuch tag so a workbench column move survives a refresh.
        let reflected: Record<Bucket, TriageThread[]>;
        try { reflected = await reflectLiveBuckets({
          act: bucketThreads(triage, "act"),
          look: bucketThreads(triage, "look"),
          bulk: bucketThreads(triage, "bulk"),
          junk: bucketThreads(triage, "junk"),
        }, readInbox, action === "digest"); } catch {
          return mcpError({ type: "COMMAND_FAILED", message: "Cannot verify inbox membership. Open aerc or refresh." });
        }
        const act = reflected.act;
        const look = reflected.look;
        const bulk = reflected.bulk;
        const junk = reflected.junk;

        // Counts derive from the REFLECTED arrays (post-move), not the stale
        // cached stats — a move shifts a thread between buckets at read time.
        const actCount = triage.stats?.act_count ?? act.length;
        const lookCount = triage.stats?.look_count ?? look.length;
        const bulkCount = triage.stats?.bulk_count ?? bulk.length;
        const junkCount = triage.stats?.junk_count ?? junk.length;
        const totalUnread = triage?.total_unread ?? 0;
        const generatedAt = triage?.generated_at ?? null;

        // Compact legacy data form — stable regardless of action.
        const compact = {
          generated_at: generatedAt,
          total_unread: totalUnread,
          stats: {
            act_count: actCount,
            look_count: lookCount,
            bulk_count: bulkCount,
            junk_count: junkCount,
          },
        };

        if (action === "digest") {
          // Eight visible Now items, actions first; reading does not remove them.
          const items = [...act.map(t => toCard(t, "act")),
                         ...look.map(t => toCard(t, "look"))];
          return { status: "ok", message: "Actionable mail", data: compact,
            view: contract("list", "Mail needing attention", {
              items: items.slice(0, 8), total: items.length,
              remaining: Math.max(0, items.length - 8),
              summary: `${actCount} act · ${lookCount} look · classified ${generatedAt ?? "unknown"}`,
            }, { generated_at: generatedAt, source: "hwc_mail_triage" }) };
        }

        if (action === "summary") {
          const highlights = act.slice(0, 5).map((t) => t.subject);
          const summaryText = triage
            ? `${totalUnread} unread (as of ${clockFromIso(generatedAt ?? undefined)})`
            : "no triage yet";
          return {
            status: "ok",
            message: triage
              ? `Mail: ${actCount} act, ${lookCount} look, ${bulkCount} later, ${junkCount} junk`
              : "No cached mail triage found",
            data: compact,
            view: contract(
              "text",
              "Mail",
              {
                greeting: `${actCount} act · ${lookCount} look · ${bulkCount} later · ${junkCount} junk`,
                summary: summaryText,
                highlights,
              },
              { generated_at: generatedAt, source: "hwc_mail_triage" },
            ),
          };
        }

        // action === "board" (default)
        const columns = [
          { id: "act", title: "Act", cards: act.map((t) => toCard(t, "act")) },
          { id: "look", title: "Look", cards: look.map((t) => toCard(t, "look")) },
          { id: "bulk", title: "Later", cards: bulk.map((t) => toCard(t, "bulk")) },
          { id: "junk", title: "Junk", cards: junk.map((t) => toCard(t, "junk")) },
        ];

        return {
          status: "ok",
          message: triage
            ? `Mail board: ${actCount} act, ${lookCount} look, ${bulkCount} later, ${junkCount} junk`
            : "No cached mail triage found — empty board",
          data: compact,
          view: contract(
            "kanban",
            "Mail Triage",
            { columns },
            { generated_at: generatedAt, total_unread: totalUnread, source: "hwc_mail_triage" },
          ),
        };
      },
    },
  ];
}
