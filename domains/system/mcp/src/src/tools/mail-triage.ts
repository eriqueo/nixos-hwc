/**
 * hwc_mail_triage — read the CACHED mail-triage from the morning-briefing pipeline.
 *
 * READ-ONLY: this tool does NOT run notmuch or Claude. It reads the briefing
 * JSON produced daily by domains/business/morning-briefing (run.sh injects a
 * `.mail_triage` key into output/briefing.json — see that dir's CLAUDE.md/run.sh)
 * and reshapes the cached triage into the Universal Result Contract.
 *
 * Path is late-bound from env HWC_BRIEFING_JSON, defaulting to the real
 * pipeline output path. Missing/unparseable file or section → EMPTY-but-valid
 * result; the tool NEVER throws.
 */

import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
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
 * workbench "move between columns" (which retags via hwc_mail set-triage)
 * survives a refresh WITHOUT re-running the daily briefing. The briefing
 * remains the content source (subject/summary/sender); the tag is the source
 * of truth for PLACEMENT. A thread carrying no triage/* tag (never moved)
 * keeps its cached bucket. notmuch unavailable → cached buckets unchanged.
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
  if (liveBucketOf.size === 0) return cached;

  const out: Record<Bucket, TriageThread[]> = { urgent: [], review: [], noise: [] };
  for (const bucket of TRIAGE_BUCKETS) {
    for (const thread of cached[bucket as Bucket]) {
      const live = liveBucketOf.get(thread.thread_id) ?? (bucket as Bucket);
      out[live].push(thread);
    }
  }
  return out;
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
        "Read the CACHED mail triage from the morning-briefing pipeline (output/briefing.json .mail_triage). " +
        "READ-ONLY: does not run notmuch or Claude — reflects the last daily briefing run. " +
        "action=board (default) returns a kanban of Urgent/Review/Noise columns; action=summary returns a compact text overview. " +
        "If no triage has been produced yet, returns an empty-but-valid result.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["board", "summary"],
            default: "board",
            description: "board = kanban of triage buckets; summary = compact text counts + top urgent subjects",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        const action = (args.action as string) || "board";
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
