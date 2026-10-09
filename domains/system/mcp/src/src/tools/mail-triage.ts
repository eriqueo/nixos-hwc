/**
 * hwc_mail_triage — the mail domain's Triage Surface Contract tool.
 *
 * READS (board/summary) come from the CACHED mail-triage produced daily by
 * domains/business/morning-briefing (run.sh injects a `.mail_triage` key into
 * output/briefing.json), re-stageed by LIVE notmuch state/* tags so human
 * decisions persist. Completed threads have no active state and disappear.
 *
 * WRITES are the generic workbench card_actions actions ({action, id[,target]}):
 * state-<state> / move, archive, and trash route through the classifier ledger,
 * the same authoritative human-decision path as aerc. Never runs an LLM.
 *
 * Path is late-bound from env HWC_BRIEFING_JSON, defaulting to the real
 * pipeline output path. Missing/unparseable file or failed live search → coded read failure; writes fail loud (a workbench write must never fake success).
 */

import { execFile } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";
import { mcpError } from "../errors.js";
import { mailThreadsByState, MAIL_STATES, MAIL_ACTION_STATE, MAIL_STATE_DISPLAY_NAMES, mailStateTag, mailTagActions, classifierMutation, classifierMutationError, acceptedMailCommand } from "./mail.js";

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
  /** Mailbox domain the classifier routed the thread to (hwc, datax, family, …). */
  domain?: string;
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
  threads_by_state?: Record<string, TriageThread[]>;
  stats: Record<string, number>;
  routing_rules?: unknown[];
}

type State = string;

const emptyStates = (): Record<State, TriageThread[]> =>
  Object.fromEntries(MAIL_STATES.map(state => [state, []]));

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

/** Defensive accessor: always returns an array of threads for a state. */
function stateThreads(triage: MailTriage | null, state: State): TriageThread[] {
  const arr = mailThreadsByState<TriageThread>(triage)[state];
  return Array.isArray(arr) ? arr : [];
}

const NOTMUCH_CANDIDATES = ["notmuch", "/etc/profiles/per-user/eric/bin/notmuch"];

type Inbox = Map<string, Set<string>>;

/** One scan, bounded at 3.5s/2MiB; never fan out per state under the gateway CPU quota. */
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
          `(${MAIL_STATES.map(state => `tag:${mailStateTag(state)}`).join(" OR ")}) AND (${ids.map(id => `thread:${id}`).join(" OR ")})`],
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
 * Re-state the cached snapshot by LIVE `state/<state>` tags.
 * WITHOUT re-running the daily briefing. The briefing remains the content
 * source (subject/summary/sender); the tag is the source of truth for
 * PLACEMENT. A thread carrying no active state is completed and is dropped,
 * so archive never resurrects from stale JSON.
 */
export async function reflectLiveStates(
  cached: Record<State, TriageThread[]>,
  readInbox: (ids: readonly string[]) => Promise<Inbox> = notmuchInbox,
  _unreadOnly = false,
): Promise<Record<State, TriageThread[]>> {
  // Only cached threads can appear on this surface. Scanning the entire inbox
  // starves khal under the gateway CPU quota. Bound argv/query work at 512 IDs;
  // overflow or invalid cache identity fails visibly, never falls back to all mail.
  const ids = [...new Set(MAIL_STATES.flatMap(state =>
    (cached[state] ?? []).map(thread => thread.thread_id)))];
  if (ids.length > 512 || ids.some(id => typeof id !== "string" || !/^[0-9a-f]{1,64}$/.test(id))) {
    throw Error("Mail triage requires at most 512 valid hexadecimal thread IDs");
  }
  if (ids.length === 0) return emptyStates();
  const inbox = await readInbox(ids);
  const seen = new Set<string>();
  const out = emptyStates();
  for (const state of MAIL_STATES) {
    for (const thread of cached[state] ?? []) {
      const tags = inbox.get(thread.thread_id);
      if (!tags || seen.has(thread.thread_id)) continue;
      seen.add(thread.thread_id);
      // During new-reply ingestion an old DID plus the new message's DO can
      // briefly coexist. Contract order is conservative: confirmed DO wins
      // before DONT KNOW, which wins over a stale completed workflow State.
      // This precedence remains defined by the contract until the classifier
      // normalizes the whole thread.
      const live = MAIL_STATES.find(state => tags.has(mailStateTag(state))) as State | undefined;
      if (live) out[live].push(thread);
    }
  }
  return out;
}

/* ─── Write actions (generic workbench card_actions path) ──────────────────── */

const WRITE_VERBS = ["move", "archive", "trash", "mark-read", "retriage"] as const;

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

/**
 * Map a thread to a kanban card. `tag` and `reason` are the workbench card
 * presentation fields: the tag is the routed mailbox domain (present on every
 * classified thread), the reason is the classifier's own why, when it gave one.
 * Absent fields are omitted, so workbench falls back to `summary`.
 */
function toCard(thread: TriageThread, state: State) {
  return {
    id: thread.thread_id,
    kind: "mail",
    label: thread.subject,
    priority: state === MAIL_ACTION_STATE ? "critical" : state === "junk" ? "low" : "normal",
    sender: thread.sender ?? thread.from_name ?? thread.from_address ?? "?",
    summary: thread.summary,
    suggested_action: thread.suggested_action,
    urgency_reason: thread.urgency_reason,
    date: thread.date_relative,
    tag: thread.domain || undefined,
    reason: thread.urgency_reason || thread.suggested_action || undefined,
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
        `Mail workflow board. READS: action=board (default) returns ${MAIL_STATES.map(state => MAIL_STATE_DISPLAY_NAMES[state]).join("/")} from cached Laya content ` +
        "reflected through live state/* tags; action=summary is compact; action=digest returns up to eight DO items. " +
        "Writes use the same durable human-decision ledger as aerc.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: [
              "board", "summary", "digest",
              ...MAIL_STATES.map((state) => `state-${state}`),
              ...WRITE_VERBS,
            ],
            default: "board",
            description:
              "board/summary/digest = reads; state-<state>, move (+target), archive, trash, mark-read = per-thread writes (require id)",
          },
          id: {
            type: "string",
            description: "[writes] notmuch thread id (hex, no 'thread:' prefix) — the kanban card id",
          },
          target: {
            type: "string",
            enum: [...MAIL_STATES],
            description: "[move] destination workflow state",
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
          const requestedState = action === "move"
            ? args.target as string | undefined
            : action.startsWith("state-") ? action.slice("state-".length) : undefined;
          if ((action === "move" || action.startsWith("state-")) &&
              (!requestedState || !MAIL_STATES.includes(requestedState))) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `unknown verb or missing/invalid target for '${action}'`,
              suggestion: `Verbs: ${MAIL_STATES.map((state) => `state-${state}`).join(", ")}, move (target=${MAIL_STATES.join("|")}), archive, trash, mark-read`,
            });
          }
          if (requestedState || action === "archive" || action === "trash") {
            const outcome = await classifierMutation(`thread:${id}`, requestedState
              ? {kind: "state", value: requestedState}
              : {kind: "outcome", value: action === "archive" ? "done" : "trash"});
            if (!("accepted" in outcome)) return classifierMutationError(outcome, `thread:${id}`);
            return {status:"ok",message:`Accepted ${action}. Remote completion is pending.`,
              data:{action,id,state:requestedState ?? null,...acceptedMailCommand(outcome.accepted)}};
          } else if (action === "mark-read") {
            const err = await notmuchTagThread(id, mailTagActions().read);
            if (err) return mcpError({type: "COMMAND_FAILED", message: "Mark-read failed", error: err});
          } else return mcpError({type: "VALIDATION_ERROR", message: "Unknown workflow action"});
          return {
            status: "ok",
            message: `${action} → thread:${id}`,
            data: { action, id, state: requestedState ?? null },
          };
        }

        // ── reads ──
        const triage = await loadTriage(briefingPath);

        if (!triage) return mcpError({ type: "UNAVAILABLE", message: "Mail digest is unavailable. Open aerc or run mail triage." });
        // Reflect persisted decisions from their live active-state tag.
        let reflected: Record<State, TriageThread[]>;
        try { reflected = await reflectLiveStates(Object.fromEntries(MAIL_STATES.map(state =>
          [state, stateThreads(triage, state)])), readInbox, action === "digest"); } catch {
          return mcpError({ type: "COMMAND_FAILED", message: "Cannot verify inbox membership. Open aerc or refresh." });
        }
        const doMail = reflected[MAIL_ACTION_STATE];

        // Counts derive from the REFLECTED arrays (post-move), not the stale
        // cached stats — a move shifts a thread between stages at read time.
        const doCount = doMail.length;
        const stateCounts = Object.fromEntries(MAIL_STATES.map(state => [`${state}_count`, reflected[state].length]));
        const countsText = MAIL_STATES.map(state => `${reflected[state].length} ${MAIL_STATE_DISPLAY_NAMES[state]}`).join(" · ");
        const totalUnread = triage?.total_unread ?? 0;
        const generatedAt = triage?.generated_at ?? null;
        const routingRuleCount = Array.isArray(triage?.routing_rules)
          ? triage.routing_rules.length
          : 0;

        // Compact legacy data form — stable regardless of action.
        const compact = {
          generated_at: generatedAt,
          total_unread: totalUnread,
          stats: stateCounts,
          routing_rule_count: routingRuleCount,
        };

        if (action === "digest") {
          const items = doMail.map(t => toCard(t, "do"));
          return { status: "ok", message: "Mail to do", data: compact,
            view: contract("list", "Mail to do", {
              items: items.slice(0, 8), total: items.length,
              remaining: Math.max(0, items.length - 8),
              summary: `${countsText} · ${routingRuleCount} routing rule${routingRuleCount === 1 ? "" : "s"} · classified ${generatedAt ?? "unknown"}`,
            }, { generated_at: generatedAt, source: "hwc_mail_triage" }) };
        }

        if (action === "summary") {
          const highlights = doMail.slice(0, 5).map((t) => t.subject);
          const summaryText = triage
            ? `${totalUnread} unread (as of ${clockFromIso(generatedAt ?? undefined)})`
            : "no triage yet";
          return {
            status: "ok",
            message: triage
              ? `Mail: ${countsText}`
              : "No cached mail triage found",
            data: compact,
            view: contract(
              "text",
              "Mail",
              {
                greeting: countsText,
                summary: summaryText,
                highlights,
              },
              { generated_at: generatedAt, source: "hwc_mail_triage" },
            ),
          };
        }

        // action === "board" (default)
        const stages = MAIL_STATES.map(state => ({id: state, title: MAIL_STATE_DISPLAY_NAMES[state],
          cards: reflected[state].map(thread => toCard(thread, state))}));

        return {
          status: "ok",
          message: triage
            ? `Mail board: ${countsText}`
            : "No cached mail triage found — empty board",
          data: compact,
          view: contract(
            "kanban",
            "Mail Triage",
            { stages },
            { generated_at: generatedAt, total_unread: totalUnread, source: "hwc_mail_triage" },
          ),
        };
      },
    },
  ];
}
