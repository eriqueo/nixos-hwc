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

import { readFile } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";

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

        const urgent = bucketThreads(triage, "urgent");
        const review = bucketThreads(triage, "review");
        const noise = bucketThreads(triage, "noise");

        const urgentCount = triage?.stats?.urgent_count ?? urgent.length;
        const reviewCount = triage?.stats?.review_count ?? review.length;
        const noiseCount = triage?.stats?.noise_count ?? noise.length;
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
