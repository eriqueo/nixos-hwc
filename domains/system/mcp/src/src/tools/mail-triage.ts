/**
 * hwc_mail_triage — the mail domain's Triage Surface Contract tool.
 *
 * READS (board/summary) come from the CACHED mail-triage produced daily by
 * domains/business/morning-briefing (run.sh injects a `.mail_triage` key into
 * output/briefing.json), re-bucketed by the LIVE notmuch triage/* tags so
 * moves persist, and filtered to threads still in the inbox.
 *
 * WRITES are the generic workbench card_actions verbs ({action, id[,target]}):
 * triage-<bucket> / move (replace the triage/* tag set), archive, trash,
 * flag-action — all plain notmuch tag ops on `thread:<id>`, the same store
 * aerc and the briefing read. Never runs Claude.
 *
 * Path is late-bound from env HWC_BRIEFING_JSON, defaulting to the real
 * pipeline output path. Missing/unparseable file or section → EMPTY-but-valid
 * result for reads; writes fail loud (a workbench write must never fake success).
 */

import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError } from "../errors.js";
import { TRIAGE_BUCKETS, triageTag } from "./mail.js";

/** Default briefing output path (run.sh writes here, then injects .mail_triage). */
const DEFAULT_BRIEFING_JSON =
  "/home/eric/.nixos/domains/business/morning-briefing/output/briefing.json";

/** A single triaged thread as produced by the mail-triage prompt. */
interface TriageThread {
  thread_id: string;
  subject: string;
  from_name: string;
  from_address: string;
  date_relative: string;
  tags: string[];
  has_attachment: boolean;
  summary: string;
  suggested_action: string;
  urgency_reason?: string;
}

interface MailTriage {
  generated_at: string;
  query_window_hours: number;
  total_unread: number;
  buckets: {
    urgent: TriageThread[];
    review: TriageThread[];
    noise: TriageThread[];
  };
  stats: {
    urgent_count: number;
    review_count: number;
    noise_count: number;
  };
}

type Bucket = "urgent" | "review" | "noise";

const PRIORITY: Record<Bucket, "critical" | "normal" | "low"> = {
  urgent: "critical",
  review: "normal",
  noise: "low",
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

/** Run notmuch search returning bare thread ids (no "thread:" prefix). Empty on any failure. */
function notmuchThreadIds(query: string): Promise<Set<string>> {
  return new Promise((resolve) => {
    const tryBin = (i: number): void => {
      if (i >= NOTMUCH_CANDIDATES.length) {
        resolve(new Set());
        return;
      }
      execFile(
        NOTMUCH_CANDIDATES[i],
        ["search", "--output=threads", query],
        { timeout: 5000, maxBuffer: 2 * 1024 * 1024 },
        (err, stdout) => {
          if (err && (err as NodeJS.ErrnoException).code === "ENOENT") {
            tryBin(i + 1);
            return;
          }
          if (err) {
            resolve(new Set());
            return;
          }
          const ids = new Set<string>();
          for (const line of (stdout || "").split("\n")) {
            const id = line.trim().replace(/^thread:/, "");
            if (id) ids.add(id);
          }
          resolve(ids);
        },
      );
    };
    tryBin(0);
  });
}

/**
 * Re-bucket the cached triage by the LIVE notmuch `triage/<bucket>` tags so a
 * workbench "move between columns" (a triage/* retag) survives a refresh
 * WITHOUT re-running the daily briefing. The briefing remains the content
 * source (subject/summary/sender); the tag is the source of truth for
 * PLACEMENT. A thread carrying no triage/* tag (never moved) keeps its cached
 * bucket. Threads no longer in the inbox (archived/trashed since the cache
 * was written — including via this tool's own verbs) are dropped, so an
 * archive durably removes the card instead of resurrecting on refresh.
 * notmuch unavailable → cached buckets unchanged (defensive: never empty the
 * board because a shell-out failed).
 */
async function reflectLiveBuckets(
  cached: Record<Bucket, TriageThread[]>,
): Promise<Record<Bucket, TriageThread[]>> {
  // thread_id → live bucket (from the triage/* tags). Only tagged threads appear.
  const liveBucketOf = new Map<string, Bucket>();
  for (const bucket of TRIAGE_BUCKETS) {
    const ids = await notmuchThreadIds(`tag:${triageTag(bucket)}`);
    if (ids.size === 0) continue;
    for (const id of ids) liveBucketOf.set(id, bucket as Bucket);
  }

  // Live inbox membership: a cached thread that left the inbox leaves the
  // board. An empty set means notmuch failed (a truly empty inbox still
  // returns the board's threads only if they match) — keep everything then.
  const inboxIds = await notmuchThreadIds("tag:inbox AND NOT tag:trash");

  const out: Record<Bucket, TriageThread[]> = { urgent: [], review: [], noise: [] };
  for (const bucket of TRIAGE_BUCKETS) {
    for (const thread of cached[bucket as Bucket]) {
      if (inboxIds.size > 0 && !inboxIds.has(thread.thread_id)) continue;
      const live = liveBucketOf.get(thread.thread_id) ?? (bucket as Bucket);
      out[live].push(thread);
    }
  }
  return out;
}

/* ─── Write verbs (generic workbench card_actions path) ──────────────────── */

/** Tag ops per verb. triage-<bucket> and move replace the triage/* set. */
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
  if (verb === "archive") return ["+archive", "-inbox"];
  if (verb === "trash") return ["+trash", "-inbox", "-unread"];
  if (verb === "flag-action") return ["+action"];
  return null;
}

const WRITE_VERBS = ["move", "archive", "trash", "flag-action"] as const;

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
    sender: thread.from_name,
    summary: thread.summary,
    suggested_action: thread.suggested_action,
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

export function mailTriageTools(): ToolDef[] {
  const briefingPath = process.env.HWC_BRIEFING_JSON || DEFAULT_BRIEFING_JSON;

  return [
    {
      name: "hwc_mail_triage",
      description:
        "Mail triage board (Triage Surface Contract). READS: action=board (default) returns a kanban of " +
        "Urgent/Review/Noise columns from the cached morning-briefing triage, re-bucketed by the live " +
        "notmuch triage/* tags and filtered to threads still in the inbox; action=summary returns a compact " +
        "text overview. WRITES (per-card verbs, require id): action=triage-urgent|triage-review|triage-noise " +
        "or action=move with target=<bucket> replace the thread's triage/* tag set; action=archive|trash " +
        "de-inbox the thread; action=flag-action adds the +action flag. Writes hit the same notmuch tags " +
        "aerc and the briefing read. Never runs Claude.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: [
              "board", "summary",
              ...TRIAGE_BUCKETS.map((b) => `triage-${b}`),
              ...WRITE_VERBS,
            ],
            default: "board",
            description:
              "board/summary = reads; triage-<bucket>, move (+target), archive, trash, flag-action = per-thread writes (require id)",
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

        // ── writes: {action, id[, target]} — the generic card_actions path ──
        if (action !== "board" && action !== "summary") {
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
              suggestion: `Verbs: ${TRIAGE_BUCKETS.map((b) => `triage-${b}`).join(", ")}, move (target=${TRIAGE_BUCKETS.join("|")}), archive, trash, flag-action`,
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

        // Reflect any persisted moves: re-bucket cached threads by their live
        // triage/* notmuch tag so a workbench column move survives a refresh.
        const reflected = await reflectLiveBuckets({
          urgent: bucketThreads(triage, "urgent"),
          review: bucketThreads(triage, "review"),
          noise: bucketThreads(triage, "noise"),
        });
        const urgent = reflected.urgent;
        const review = reflected.review;
        const noise = reflected.noise;

        // Counts derive from the REFLECTED arrays (post-move), not the stale
        // cached stats — a move shifts a thread between buckets at read time.
        const urgentCount = urgent.length;
        const reviewCount = review.length;
        const noiseCount = noise.length;
        const totalUnread = triage?.total_unread ?? 0;
        const generatedAt = triage?.generated_at ?? null;

        // Compact legacy data form — stable regardless of action.
        const compact = {
          generated_at: generatedAt,
          total_unread: totalUnread,
          stats: {
            urgent_count: urgentCount,
            review_count: reviewCount,
            noise_count: noiseCount,
          },
        };

        if (action === "summary") {
          const highlights = urgent.slice(0, 5).map((t) => t.subject);
          const summaryText = triage
            ? `${totalUnread} unread (as of ${clockFromIso(generatedAt ?? undefined)})`
            : "no triage yet";
          return {
            status: "ok",
            message: triage
              ? `Mail triage: ${urgentCount} urgent, ${reviewCount} review, ${noiseCount} noise`
              : "No cached mail triage found",
            data: compact,
            view: contract(
              "text",
              "Mail",
              {
                greeting: `${urgentCount} urgent · ${reviewCount} review · ${noiseCount} noise`,
                summary: summaryText,
                highlights,
              },
              { generated_at: generatedAt, source: "hwc_mail_triage" },
            ),
          };
        }

        // action === "board" (default)
        const columns = [
          { id: "urgent", title: "Urgent", cards: urgent.map((t) => toCard(t, "urgent")) },
          { id: "review", title: "Review", cards: review.map((t) => toCard(t, "review")) },
          { id: "noise", title: "Noise", cards: noise.map((t) => toCard(t, "noise")) },
        ];

        return {
          status: "ok",
          message: triage
            ? `Mail triage board: ${urgentCount} urgent, ${reviewCount} review, ${noiseCount} noise`
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
