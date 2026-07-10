/**
 * hwc_mail — consolidated mail tool (search, read, send, reply, tag, sync, health, accounts, folders).
 */

import { execFile, spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { readFile, stat, readdir } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { getServiceStatus } from "../executors/systemd.js";
import { log } from "../log.js";
import { mcpError, catchError } from "../errors.js";

/* ════════════════════════════════════════════════════════════════ */
/*  Constants                                                      */
/* ════════════════════════════════════════════════════════════════ */

const HOME = homedir();
const MAIL_HEALTH_STATE = join(HOME, ".local/state/mail-health");
const MBSYNC_SUCCESS_MARKER = join(HOME, ".cache/mbsync-last-success");
const MAILDIR = join(HOME, "400_mail/Maildir");
const SYNC_MAIL = join(HOME, ".local/bin/sync-mail");

/* ─── Taxonomy (canonical, baked from nixos-hwc domains/mail/taxonomy/) ────
 * The tag vocabulary is loaded at startup from HWC_MAIL_TAXONOMY_FILE — a
 * store-path JSON the gateway's NixOS module bakes from the same data.nix
 * that generates the notmuch rules, aerc tags, and the triage prompt (see
 * docs/plans/unified-triage-architecture.md). The literals below are a
 * boot-robustness fallback ONLY (env unset / file unreadable), never the
 * source of truth — a warning is logged whenever the fallback is used. */
interface MailTaxonomy {
  triage: { buckets: string[]; tagPrefix: string };
  categories: string[];
  flags: string[];
  /** Flags bulk clear operations must never remove (e.g. `keep`). */
  protectedFlags?: string[];
}

const FALLBACK_TAXONOMY: MailTaxonomy = {
  triage: { buckets: ["urgent", "review", "noise"], tagPrefix: "triage/" },
  categories: [
    "office", "work", "hwcmt",
    "finance", "bank", "insurance",
    "personal", "family", "eriqueokeefe",
    "admin", "coaching",
    "tech", "aerc", "website",
  ],
  flags: ["action", "pending"],
  protectedFlags: [],
};

function loadTaxonomy(): MailTaxonomy {
  const file = process.env.HWC_MAIL_TAXONOMY_FILE;
  if (!file) {
    log.warn("mail: HWC_MAIL_TAXONOMY_FILE unset — using compiled-in fallback taxonomy");
    return FALLBACK_TAXONOMY;
  }
  try {
    const parsed = JSON.parse(readFileSync(file, "utf8"));
    if (
      !Array.isArray(parsed?.triage?.buckets) || parsed.triage.buckets.length === 0 ||
      typeof parsed?.triage?.tagPrefix !== "string" ||
      !Array.isArray(parsed?.categories) || !Array.isArray(parsed?.flags)
    ) {
      throw new Error("missing/invalid triage.buckets, triage.tagPrefix, categories, or flags");
    }
    log.info(`mail: taxonomy loaded from ${file}`);
    return parsed as MailTaxonomy;
  } catch (err) {
    log.warn(`mail: failed to load taxonomy from ${file} (${String(err)}) — using compiled-in fallback`);
    return FALLBACK_TAXONOMY;
  }
}

const TAXONOMY = loadTaxonomy();
const CATEGORY_TAGS = TAXONOMY.categories;
const FLAG_TAGS = TAXONOMY.flags;
const JUNK_TAGS = ["important", "flagged", "starred"];

/* ─── Triage buckets (tag-backed) ──────────────────────────────────────────
 * The Mail-triage kanban's "move between columns" must PERSIST, so the bucket
 * is a notmuch tag `triage/<bucket>`. The bucket→tag mapping is shared by:
 *   - the morning-briefing pipeline (writes triage/<bucket> when it classifies)
 *   - replace-triage-bucket here (remove other triage/* + add the target)
 *   - hwc_mail_triage (re-buckets cached threads by their live triage/* tag)
 * All of them derive from the taxonomy, so they cannot drift. */
export const TRIAGE_BUCKETS: readonly string[] = TAXONOMY.triage.buckets;
export type TriageBucket = string;
/** notmuch tag for a triage bucket, e.g. "urgent" → "triage/urgent". */
export function triageTag(bucket: string): string {
  return `${TAXONOMY.triage.tagPrefix}${bucket}`;
}
/** Tag ops that REPLACE the triage bucket: drop every triage/* then add target. */
function replaceTriageOps(target: TriageBucket): string[] {
  const ops = TRIAGE_BUCKETS.filter((b) => b !== target).map((b) => `-${triageTag(b)}`);
  ops.push(`+${triageTag(target)}`);
  return ops;
}

const SAVED_SEARCHES: Record<string, string> = {
  inbox: "tag:inbox AND NOT tag:trash",
  unread: "tag:unread AND NOT tag:trash",
  sent: "tag:sent",
  drafts: "tag:draft",
  archive: "tag:archive AND NOT tag:trash",
  trash: "tag:trash",
  spam: "tag:spam",
  important: "tag:important AND NOT tag:trash",
  // Per-tag searches generated from the taxonomy (flags + categories), so a
  // vocabulary change lands here without touching this file.
  ...Object.fromEntries(
    [...FLAG_TAGS, ...CATEGORY_TAGS].map((t) => [t, `(tag:${t} AND NOT tag:trash) AND tag:inbox`]),
  ),
  ...Object.fromEntries(
    CATEGORY_TAGS.map((t) => [`label:${t}`, `tag:${t} AND NOT tag:trash`]),
  ),
  "label:hide": "tag:hide",
  unified: "tag:inbox",
  "inbox:hwc": "tag:inbox AND tag:hwc",
  "inbox:proton-hwc": "tag:inbox AND tag:proton-hwc",
  "inbox:proton-personal": "tag:inbox AND tag:proton-personal",
  "all:work": "tag:inbox AND tag:hwc",
  "all:personal": "tag:inbox AND tag:proton-personal",
};

const ACCOUNTS = [
  {
    name: "proton",
    msmtpAccount: "proton-hwc",
    email: "eric@iheartwoodcraft.com",
    type: "proton-bridge",
    sync: true,
    send: true,
    primary: true,
    identities: [
      { msmtpAccount: "proton-personal", email: "eriqueo@proton.me" },
      { msmtpAccount: "proton-office", email: "office@iheartwoodcraft.com" },
    ],
  },
  {
    name: "gmail-personal",
    msmtpAccount: "gmail-personal",
    email: "eriqueokeefe@gmail.com",
    type: "gmail",
    sync: false,
    send: true,
    primary: false,
    identities: [],
  },
  {
    name: "gmail-business",
    msmtpAccount: "gmail-business",
    email: "heartwoodcraftmt@gmail.com",
    type: "gmail",
    sync: false,
    send: true,
    primary: false,
    identities: [],
  },
];

const FROM_MAP: Record<string, string> = {};
for (const acct of ACCOUNTS) {
  FROM_MAP[acct.msmtpAccount] = acct.email;
  for (const id of acct.identities) {
    FROM_MAP[id.msmtpAccount] = id.email;
  }
}

/* ════════════════════════════════════════════════════════════════ */
/*  Binary resolution                                              */
/* ════════════════════════════════════════════════════════════════ */

const NOTMUCH_CANDIDATES = ["notmuch", `/etc/profiles/per-user/eric/bin/notmuch`];
const MSMTP_CANDIDATES = ["msmtp", `/etc/profiles/per-user/eric/bin/msmtp`];

let _notmuch: string | null = null;
let _msmtp: string | null = null;

async function resolveBin(candidates: string[]): Promise<string> {
  for (const bin of candidates) {
    try {
      await new Promise<void>((resolve, reject) => {
        execFile(bin, ["--version"], { timeout: 3000 }, (err) => {
          if (err && (err as NodeJS.ErrnoException).code === "ENOENT") reject(err);
          else resolve();
        });
      });
      return bin;
    } catch {
      continue;
    }
  }
  throw new Error(`Binary not found in: ${candidates.join(", ")}`);
}

async function notmuchBin(): Promise<string> {
  if (!_notmuch) _notmuch = await resolveBin(NOTMUCH_CANDIDATES);
  return _notmuch;
}

async function msmtpBin(): Promise<string> {
  if (!_msmtp) _msmtp = await resolveBin(MSMTP_CANDIDATES);
  return _msmtp;
}

/* ════════════════════════════════════════════════════════════════ */
/*  Executors                                                      */
/* ════════════════════════════════════════════════════════════════ */

function notmuchExec(
  bin: string,
  args: string[],
  opts: { timeout?: number; maxBuffer?: number } = {},
): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const { timeout = 15000, maxBuffer = 5 * 1024 * 1024 } = opts;
  return new Promise((resolve) => {
    log.debug("notmuch", { args });
    execFile(bin, args, { timeout, maxBuffer }, (error, stdout, stderr) => {
      const code = error && "code" in error ? (error.code as number) : 0;
      resolve({
        exitCode: typeof code === "number" ? code : 1,
        stdout: stdout?.toString() ?? "",
        stderr: stderr?.toString() ?? "",
      });
    });
  });
}

function msmtpSend(
  bin: string,
  account: string,
  recipients: string[],
  message: string,
): Promise<{ exitCode: number; stderr: string }> {
  return new Promise((resolve) => {
    const args = ["-a", account, "--", ...recipients];
    log.debug("msmtp", { args });
    const proc = spawn(bin, args, { timeout: 30000 });
    let stderr = "";
    proc.stderr.on("data", (d: Buffer) => {
      stderr += d.toString();
    });
    proc.on("close", (code) => resolve({ exitCode: code ?? 1, stderr }));
    proc.on("error", (err) => resolve({ exitCode: 1, stderr: err.message }));
    proc.stdin.write(message);
    proc.stdin.end();
  });
}

/* ════════════════════════════════════════════════════════════════ */
/*  Helpers                                                        */
/* ════════════════════════════════════════════════════════════════ */

async function readSafe(path: string): Promise<string | null> {
  try {
    return (await readFile(path, "utf-8")).trim();
  } catch {
    return null;
  }
}

function resolveQuery(query: string): string {
  return SAVED_SEARCHES[query] ?? query;
}

function exclusiveCategoryOps(category: string): string[] {
  const ops = [`+${category}`];
  for (const c of CATEGORY_TAGS) {
    if (c !== category) ops.push(`-${c}`);
  }
  return ops;
}

function clearAllCustomOps(): string[] {
  // Protected flags (e.g. `keep`, the family/friends preservation tag) are
  // never stripped by bulk clears — the keep-shield and the mail-janitor's
  // exclusions depend on them surviving.
  const protectedFlags = TAXONOMY.protectedFlags ?? [];
  return [...CATEGORY_TAGS, ...FLAG_TAGS, ...JUNK_TAGS]
    .filter((t) => !protectedFlags.includes(t))
    .map((t) => `-${t}`);
}

function flattenShow(data: unknown): unknown[] {
  const msgs: unknown[] = [];
  function walk(node: unknown): void {
    if (Array.isArray(node)) {
      for (const item of node) walk(item);
    } else if (node && typeof node === "object" && "id" in node) {
      const m = node as Record<string, unknown>;
      const extracted: Record<string, unknown> = {
        id: m.id,
        match: m.match,
        timestamp: m.timestamp,
        date_relative: m.date_relative,
        tags: m.tags,
        headers: m.headers,
      };
      if (Array.isArray(m.body)) extracted.body = extractText(m.body);
      msgs.push(extracted);
    }
  }
  walk(data);
  return msgs;
}

function stripHtml(html: string): string {
  return html
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<\/div>/gi, "\n")
    .replace(/<\/li>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function extractText(parts: unknown[]): string[] {
  const texts: string[] = [];
  function walk(part: unknown): void {
    if (Array.isArray(part)) {
      for (const p of part) walk(p);
    } else if (part && typeof part === "object") {
      const p = part as Record<string, unknown>;
      if (p["content-type"] === "text/plain" && typeof p.content === "string") {
        texts.push(p.content);
      } else if (p["content-type"] === "text/html" && typeof p.content === "string") {
        texts.push(stripHtml(p.content as string));
      } else if (Array.isArray(p.content)) {
        for (const c of p.content) walk(c);
      }
    }
  }
  for (const part of parts) walk(part);
  return texts;
}

async function walkMaildir(
  dir: string,
  root: string,
  results: Array<{ path: string; name: string }>,
): Promise<void> {
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    const subdirs = entries.filter((e) => e.isDirectory() && !e.name.startsWith("."));
    if (entries.some((e) => e.name === "cur" && e.isDirectory())) {
      const rel = dir.slice(root.length + 1);
      if (rel) results.push({ path: dir, name: rel });
    }
    for (const sub of subdirs) {
      if (sub.name === "cur" || sub.name === "new" || sub.name === "tmp") continue;
      await walkMaildir(join(dir, sub.name), root, results);
    }
  } catch {
    /* dir not readable */
  }
}

/* ════════════════════════════════════════════════════════════════ */
/*  Exported executors (used by morning-status)                    */
/* ════════════════════════════════════════════════════════════════ */

export async function executeMailHealth(): Promise<ToolResult> {
  try {
    const result: Record<string, unknown> = {};
    const now = Math.floor(Date.now() / 1000);

    const lastHealthyRaw = await readSafe(join(MAIL_HEALTH_STATE, "last-healthy"));
    const firstFailureRaw = await readSafe(join(MAIL_HEALTH_STATE, "first-failure"));

    if (lastHealthyRaw) {
      const ts = parseInt(lastHealthyRaw, 10);
      result.lastHealthy = {
        epoch: ts,
        iso: new Date(ts * 1000).toISOString(),
        ageMinutes: Math.round((now - ts) / 60),
      };
    }
    if (firstFailureRaw) {
      const ts = parseInt(firstFailureRaw, 10);
      const downMin = Math.round((now - ts) / 60);
      result.ongoingFailure = {
        since: new Date(ts * 1000).toISOString(),
        downMinutes: downMin,
        severity: downMin >= 30 ? "critical" : "warning",
      };
    }

    try {
      const entries = await readdir(MAIL_HEALTH_STATE);
      const cooldownFiles = entries.filter((e) => e.startsWith("cooldown-"));
      if (cooldownFiles.length > 0) {
        const byLevel: Record<string, { count: number; oldest: number; newest: number }> = {};
        for (const c of cooldownFiles) {
          const level = c.replace("cooldown-", "").split("-")[0] || "unknown";
          const tsRaw = await readSafe(join(MAIL_HEALTH_STATE, c));
          const ts = tsRaw ? parseInt(tsRaw, 10) : 0;
          if (!byLevel[level]) {
            byLevel[level] = { count: 0, oldest: ts || Infinity, newest: 0 };
          }
          byLevel[level].count++;
          if (ts && ts < byLevel[level].oldest) byLevel[level].oldest = ts;
          if (ts && ts > byLevel[level].newest) byLevel[level].newest = ts;
        }
        const cooldowns: Record<string, { count: number; oldestAt: string; newestAt: string }> = {};
        for (const [level, info] of Object.entries(byLevel)) {
          cooldowns[level] = {
            count: info.count,
            oldestAt: info.oldest !== Infinity ? new Date(info.oldest * 1000).toISOString() : "unknown",
            newestAt: info.newest > 0 ? new Date(info.newest * 1000).toISOString() : "unknown",
          };
        }
        result.cooldowns = cooldowns;
      }
    } catch {
      /* state dir may not exist yet */
    }

    try {
      const bs = await getServiceStatus("protonmail-bridge.service");
      result.bridge = {
        active: bs.activeState === "active",
        state: bs.activeState,
        uptime: bs.uptime,
        memoryUsage: bs.memoryUsage,
      };
    } catch {
      result.bridge = { active: false, error: "Service not queryable" };
    }

    try {
      const ms = await stat(MBSYNC_SUCCESS_MARKER);
      const ageMin = Math.round((Date.now() - ms.mtime.getTime()) / 60000);
      result.sync = { lastSuccess: ms.mtime.toISOString(), ageMinutes: ageMin, healthy: ageMin < 30 };
    } catch {
      result.sync = { error: "No sync marker — mbsync may not have run" };
    }

    try {
      const nm = await notmuchBin();
      const cntRes = await notmuchExec(nm, ["count"]);
      if (cntRes.exitCode === 0) {
        const total = parseInt(cntRes.stdout.trim(), 10) || 0;
        const urRes = await notmuchExec(nm, ["count", "tag:unread"]);
        const unread = urRes.exitCode === 0 ? parseInt(urRes.stdout.trim(), 10) || 0 : 0;
        result.notmuch = { totalMessages: total, unread };
      }
    } catch {
      result.notmuch = { error: "notmuch not available" };
    }

    const bridgeOk = (result.bridge as Record<string, unknown>)?.active === true;
    const syncOk = (result.sync as Record<string, unknown>)?.healthy === true;
    const hasFailure = !!firstFailureRaw;

    let status: "ok" | "partial" | "error";
    if (!hasFailure && bridgeOk && syncOk) status = "ok";
    else if (hasFailure && (result.ongoingFailure as Record<string, unknown>)?.severity === "critical")
      status = "error";
    else status = "partial";

    const parts: string[] = [];
    if (hasFailure) parts.push(`Failing ${(result.ongoingFailure as Record<string, unknown>)?.downMinutes}m`);
    parts.push(`Bridge: ${bridgeOk ? "up" : "down"}`);
    parts.push(`Sync: ${syncOk ? "fresh" : "stale"}`);

    return { status, message: parts.join(", "), data: result };
  } catch (err) {
    return catchError("INTERNAL_ERROR", "Failed to check mail health", err, "Check that mail-health timer is running and state files exist at ~/.local/state/mail-health");
  }
}

/* ════════════════════════════════════════════════════════════════ */
/*  Consolidated tool                                              */
/* ════════════════════════════════════════════════════════════════ */

export function mailTools(): ToolDef[] {
  return [
    {
      name: "hwc_mail",
      description:
        "Mail management. Actions: search, read, send, reply, tag, sync, health, accounts, folders. " +
        "Mutations route through action=tag: tag_action=archive|trash|delete (delete==trash), " +
        "or tag_action=set-triage with triage=urgent|review|noise to REPLACE the triage bucket " +
        "(removes other triage/* tags, adds the target) — the persisted backing for the triage kanban's move.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["search", "read", "send", "reply", "tag", "sync", "health", "accounts", "folders"],
            description: "Action to perform",
          },
          // [search] params
          query: {
            type: "string",
            description: "[search/tag] Notmuch query or saved search name (inbox, unread, action, label:finance, etc.)",
          },
          limit: { type: "number", description: "[search] Max results (default 20)" },
          offset: { type: "number", description: "[search] Skip first N results" },
          count_only: { type: "boolean", description: "[search] Return message count only (default false)" },
          // [read] params
          id: {
            type: "string",
            description: "[read] Thread or message ID (thread:XXXX or id:msgid@host)",
          },
          entireThread: { type: "boolean", description: "[read] Show entire thread (default false)" },
          // [send] params
          to: { type: "string", description: "[send] Recipient(s), comma-separated" },
          subject: { type: "string", description: "[send] Subject line" },
          body: { type: "string", description: "[send/reply] Plain text body" },
          from: { type: "string", description: "[send] From address (auto-set from account)" },
          cc: { type: "string", description: "[send] CC address(es)" },
          bcc: { type: "string", description: "[send] BCC address(es)" },
          account: { type: "string", description: "[send/reply] msmtp account (default proton-hwc)" },
          inReplyTo: { type: "string", description: "[send] Message-ID for threading" },
          // [reply] params
          threadId: {
            type: "string",
            description: "[reply] Thread or message ID to reply to",
          },
          replyAll: { type: "boolean", description: "[reply] Include all original recipients (default false)" },
          // [tag] params
          tag_action: {
            type: "string",
            enum: [
              "archive", "trash", "delete", "untrash", "spam", "unspam",
              "read", "unread", "clear-categories", "set-triage",
            ],
            description: "[tag] Named action (maps to correct tag combination). delete==trash. set-triage requires `triage`.",
          },
          triage: {
            type: "string",
            enum: [...TRIAGE_BUCKETS],
            description: "[tag] With tag_action=set-triage: target triage bucket. Removes other triage/* tags and adds triage/<bucket>.",
          },
          tags: {
            type: "array",
            items: { type: "string" },
            description: "[tag] Raw tag ops: '+tag' to add, '-tag' to remove",
          },
          category: {
            type: "string",
            description: `[tag] Exclusive category: ${CATEGORY_TAGS.join(", ")}`,
          },
          flag: {
            type: "string",
            description: "[tag] Additive flag: '+action', '-action', '+pending', '-pending'",
          },
          // [sync] params
          wait: {
            type: "boolean",
            description: "[sync] Wait for sync to complete (default true, max 2 min)",
          },
          // [folders] params
          folder_account: { type: "string", description: "[folders] Filter to account (e.g. 'proton')" },
        },
        required: ["action"],
      },
      handler: async (args): Promise<ToolResult> => {
        const action = args.action as string;

        // ── health ──────────────────────────────────────────────
        if (action === "health") {
          return executeMailHealth();
        }

        // ── search ──────────────────────────────────────────────
        if (action === "search") {
          try {
            const rawQuery = args.query as string;
            if (!rawQuery) {
              return mcpError({ type: "VALIDATION_ERROR", message: "query is required for action=search" });
            }
            const query = resolveQuery(rawQuery);
            const wasResolved = query !== rawQuery;
            const countOnly = (args.count_only as boolean) ?? false;
            const nm = await notmuchBin();

            if (countOnly) {
              const res = await notmuchExec(nm, ["count", query]);
              if (res.exitCode !== 0) {
                return mcpError({ type: "COMMAND_FAILED", message: "notmuch count failed", error: res.stderr.slice(0, 300), suggestion: "Check query syntax", context: { query } });
              }
              const count = parseInt(res.stdout.trim(), 10) || 0;
              return { status: "ok", message: `${count} messages`, data: { count, query } };
            }

            const lim = (args.limit as number) || 20;
            const off = (args.offset as number) || 0;

            const res = await notmuchExec(
              nm,
              ["search", "--format=json", `--limit=${lim}`, `--offset=${off}`, query],
              { timeout: 10000 },
            );
            if (res.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "notmuch search failed", error: res.stderr.slice(0, 500), suggestion: "Check query syntax. Use saved search names (inbox, action, label:finance) or raw notmuch queries.", context: { query, exitCode: res.exitCode } });
            }

            const threads = JSON.parse(res.stdout || "[]") as Array<Record<string, unknown>>;
            const slimmed = threads.map((t) => {
              const { query: qArr, ...rest } = t;
              const result: Record<string, unknown> = { ...rest };
              if (Array.isArray(qArr) && typeof qArr[0] === "string") {
                result.messageId = (qArr[0] as string).replace(/^id:/, "");
              }
              return result;
            });
            const resolvedNote = wasResolved ? ` (resolved '${rawQuery}' → '${query}')` : "";
            return {
              status: "ok",
              message: `${slimmed.length} threads (offset ${off}, limit ${lim})${resolvedNote}`,
              data: slimmed,
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Search failed", err, "Is notmuch installed and the Xapian database accessible?");
          }
        }

        // ── read ─────────────────────────────────────────────────
        if (action === "read") {
          try {
            const id = args.id as string;
            if (!id) {
              return mcpError({ type: "VALIDATION_ERROR", message: "id is required for action=read" });
            }
            const entireThread = (args.entireThread as boolean) ?? false;
            const nm = await notmuchBin();

            const res = await notmuchExec(
              nm,
              ["show", "--format=json", "--include-html", `--entire-thread=${entireThread}`, "--body=true", id],
              { timeout: 15000, maxBuffer: 10 * 1024 * 1024 },
            );
            if (res.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "notmuch show failed", error: res.stderr.slice(0, 500), suggestion: "Verify the thread/message ID format: thread:XXXX or id:msgid@host", context: { id } });
            }

            const messages = flattenShow(JSON.parse(res.stdout || "[]"));
            return { status: "ok", message: `${messages.length} message(s)`, data: messages };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Read failed", err, "Is notmuch installed and the message ID valid?");
          }
        }

        // ── tag ──────────────────────────────────────────────────
        if (action === "tag") {
          try {
            const rawQuery = args.query as string;
            if (!rawQuery) {
              return mcpError({ type: "VALIDATION_ERROR", message: "query is required for action=tag" });
            }
            const query = resolveQuery(rawQuery);
            const actionName = args.tag_action as string | undefined;
            const rawTags = args.tags as string[] | undefined;
            const category = args.category as string | undefined;
            const flag = args.flag as string | undefined;

            let ops: string[];
            let mode: string;

            if (actionName === "set-triage") {
              // Replace the triage bucket: needs an explicit target bucket.
              const target = args.triage as string | undefined;
              if (!target || !TRIAGE_BUCKETS.includes(target as TriageBucket)) {
                return mcpError({ type: "VALIDATION_ERROR", message: `tag_action=set-triage requires triage one of: ${TRIAGE_BUCKETS.join(", ")}`, suggestion: "Pass triage=urgent|review|noise" });
              }
              ops = replaceTriageOps(target as TriageBucket);
              mode = `triage:${target}`;
            } else if (actionName) {
              const actionMap: Record<string, string[]> = {
                archive: ["+archive", "-inbox"],
                // delete is an alias for trash (the kanban's destructive path).
                trash: ["+trash", "-inbox", "-unread"],
                delete: ["+trash", "-inbox", "-unread"],
                untrash: ["-trash", "+inbox"],
                spam: ["+spam", "-inbox", "-unread"],
                unspam: ["-spam", "+inbox"],
                read: ["-unread"],
                unread: ["+unread"],
                "clear-categories": clearAllCustomOps(),
              };
              ops = actionMap[actionName];
              if (!ops) {
                return mcpError({ type: "VALIDATION_ERROR", message: `Unknown action '${actionName}'. Valid: ${Object.keys(actionMap).join(", ")}`, suggestion: "Use one of the supported actions" });
              }
              mode = `action:${actionName}`;
            } else if (category) {
              if (!CATEGORY_TAGS.includes(category)) {
                return mcpError({ type: "VALIDATION_ERROR", message: `Unknown category '${category}'. Valid: ${CATEGORY_TAGS.join(", ")}`, suggestion: "Use one of the defined category tags" });
              }
              ops = exclusiveCategoryOps(category);
              mode = `category:${category}`;
            } else if (flag) {
              const flagMatch = flag.match(/^([+-])([a-zA-Z]+)$/);
              if (!flagMatch) {
                return mcpError({ type: "VALIDATION_ERROR", message: `Invalid flag format: '${flag}'. Use '+action' or '-pending'.`, suggestion: "Flag format is +name or -name where name is: " + FLAG_TAGS.join(", ") });
              }
              const [, op, name] = flagMatch;
              if (!FLAG_TAGS.includes(name)) {
                return mcpError({ type: "VALIDATION_ERROR", message: `Unknown flag '${name}'. Valid: ${FLAG_TAGS.join(", ")}`, suggestion: "Use one of the defined flag tags" });
              }
              ops = [`${op}${name}`];
              mode = `flag:${op}${name}`;
            } else if (rawTags && rawTags.length > 0) {
              for (const t of rawTags) {
                if (!/^[+-][a-zA-Z0-9_:/.@-]+$/.test(t)) {
                  return mcpError({ type: "VALIDATION_ERROR", message: `Invalid tag format: ${t}. Use +tag or -tag.`, suggestion: "Each tag op must start with + or - followed by alphanumeric/underscore characters" });
                }
              }
              ops = rawTags;
              mode = "raw";
            } else {
              return mcpError({ type: "VALIDATION_ERROR", message: "Specify tag_action, tags, category, or flag.", suggestion: "Provide one of: tag_action (named preset), tags (raw ops), category (exclusive), or flag (additive)" });
            }

            const nm = await notmuchBin();
            const res = await notmuchExec(nm, ["tag", ...ops, "--", query]);
            if (res.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "notmuch tag failed", error: res.stderr.slice(0, 500), suggestion: "Check that the query matches existing messages and the Xapian DB is writable", context: { query, ops } });
            }
            return {
              status: "ok",
              message: `[${mode}] Applied [${ops.join(", ")}] to: ${rawQuery}`,
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Tag failed", err, "Check notmuch binary and Xapian DB write permissions");
          }
        }

        // ── send ─────────────────────────────────────────────────
        if (action === "send") {
          try {
            const to = args.to as string;
            const subject = args.subject as string;
            const body = args.body as string;
            if (!to || !subject || !body) {
              return mcpError({ type: "VALIDATION_ERROR", message: "to, subject, and body are required for action=send" });
            }
            const acct = (args.account as string) || "proton-hwc";
            const cc = args.cc as string | undefined;
            const bcc = args.bcc as string | undefined;
            const inReplyTo = args.inReplyTo as string | undefined;
            const from = (args.from as string) || FROM_MAP[acct] || FROM_MAP["proton-hwc"];

            const hdrs: string[] = [
              `From: ${from}`,
              `To: ${to}`,
              `Subject: ${subject}`,
              `Date: ${new Date().toUTCString()}`,
              "MIME-Version: 1.0",
              "Content-Type: text/plain; charset=utf-8",
            ];
            if (cc) hdrs.push(`Cc: ${cc}`);
            if (inReplyTo) hdrs.push(`In-Reply-To: ${inReplyTo}`);

            const msg = hdrs.join("\r\n") + "\r\n\r\n" + body;
            const rcpts = to.split(",").map((s) => s.trim());
            if (cc) rcpts.push(...cc.split(",").map((s) => s.trim()));
            if (bcc) rcpts.push(...bcc.split(",").map((s) => s.trim()));

            const bin = await msmtpBin();
            const res = await msmtpSend(bin, acct, rcpts, msg);
            if (res.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "Send failed", error: res.stderr.slice(0, 500), suggestion: "Check msmtp config, account name, and that Proton Bridge is running", context: { account: acct, to, exitCode: res.exitCode } });
            }

            return {
              status: "ok",
              message: `Sent to ${to} via ${acct}`,
              data: { from, to, cc, subject, account: acct },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Send failed", err, "Is msmtp installed and configured? Is Proton Bridge running?");
          }
        }

        // ── reply ────────────────────────────────────────────────
        if (action === "reply") {
          try {
            const threadId = args.threadId as string;
            const body = args.body as string;
            if (!threadId || !body) {
              return mcpError({ type: "VALIDATION_ERROR", message: "threadId and body are required for action=reply" });
            }
            const replyAll = (args.replyAll as boolean) ?? false;
            const accountOverride = args.account as string | undefined;
            const nm = await notmuchBin();

            const res = await notmuchExec(
              nm,
              ["show", "--format=json", "--entire-thread=false", "--body=false", threadId],
              { timeout: 10000 },
            );
            if (res.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "Failed to read thread", error: res.stderr.slice(0, 500), suggestion: "Verify the thread/message ID format: thread:XXXX or id:msgid@host", context: { threadId } });
            }

            const messages = flattenShow(JSON.parse(res.stdout || "[]"));
            if (messages.length === 0) {
              return mcpError({ type: "NOT_FOUND", message: `No messages found for ${threadId}`, suggestion: "Check the thread ID is correct. Use hwc_mail action=search to find threads." });
            }

            const lastMsg = messages[messages.length - 1] as Record<string, unknown>;
            const headers = lastMsg.headers as Record<string, string> | undefined;
            if (!headers) {
              return mcpError({ type: "INTERNAL_ERROR", message: "Could not parse message headers", suggestion: "Try reading the thread with hwc_mail action=read first" });
            }

            const originalFrom = headers.From || "";
            const originalTo = headers.To || "";
            const originalCc = headers.Cc || "";
            const originalSubject = headers.Subject || "";
            const originalMessageId = headers["Message-ID"] || (lastMsg.id as string);

            const ourAddresses: Set<string> = new Set();
            for (const acct of ACCOUNTS) {
              ourAddresses.add(acct.email.toLowerCase());
              for (const id of acct.identities) {
                ourAddresses.add(id.email.toLowerCase());
              }
            }

            const parseAddresses = (header: string): string[] => {
              if (!header) return [];
              return header
                .split(",")
                .map((a) => {
                  const match = a.match(/<([^>]+)>/) || [null, a.trim()];
                  return match[1]?.trim() || "";
                })
                .filter((a) => a.length > 0);
            };

            const originalFromAddrs = parseAddresses(originalFrom);
            const originalToAddrs = parseAddresses(originalTo);
            const originalCcAddrs = parseAddresses(originalCc);

            let sendAccount = accountOverride;
            let fromAddress = "";

            if (!sendAccount) {
              const allRecipients = [...originalToAddrs, ...originalCcAddrs];
              for (const addr of allRecipients) {
                const lowerAddr = addr.toLowerCase();
                if (ourAddresses.has(lowerAddr)) {
                  for (const acct of ACCOUNTS) {
                    if (acct.email.toLowerCase() === lowerAddr) {
                      sendAccount = acct.msmtpAccount;
                      fromAddress = acct.email;
                      break;
                    }
                    for (const id of acct.identities) {
                      if (id.email.toLowerCase() === lowerAddr) {
                        sendAccount = id.msmtpAccount;
                        fromAddress = id.email;
                        break;
                      }
                    }
                  }
                  if (sendAccount) break;
                }
              }
            }

            if (!sendAccount) {
              const primary = ACCOUNTS.find((a) => a.primary);
              sendAccount = primary?.msmtpAccount || "proton-hwc";
              fromAddress = primary?.email || FROM_MAP[sendAccount] || "";
            }
            if (!fromAddress) {
              fromAddress = FROM_MAP[sendAccount] || "";
            }

            let replyTo: string[] = [];
            let replyCc: string[] = [];

            if (replyAll) {
              replyTo = originalFromAddrs;
              const allOthers = [...originalToAddrs, ...originalCcAddrs].filter(
                (a) => !ourAddresses.has(a.toLowerCase()),
              );
              replyCc = allOthers;
            } else {
              replyTo = originalFromAddrs;
            }

            if (replyTo.length === 0) {
              return mcpError({ type: "VALIDATION_ERROR", message: "Could not determine reply recipient from original message", suggestion: "Check that the original message has a valid From header", context: { originalFrom } });
            }

            let subject = originalSubject;
            if (!subject.toLowerCase().startsWith("re:")) {
              subject = `Re: ${subject}`;
            }

            const hdrs: string[] = [
              `From: ${fromAddress}`,
              `To: ${replyTo.join(", ")}`,
              `Subject: ${subject}`,
              `Date: ${new Date().toUTCString()}`,
              "MIME-Version: 1.0",
              "Content-Type: text/plain; charset=utf-8",
            ];
            if (replyCc.length > 0) {
              hdrs.push(`Cc: ${replyCc.join(", ")}`);
            }
            if (originalMessageId) {
              const cleanId = originalMessageId.replace(/^<|>$/g, "");
              hdrs.push(`In-Reply-To: <${cleanId}>`);
              hdrs.push(`References: <${cleanId}>`);
            }

            const msg = hdrs.join("\r\n") + "\r\n\r\n" + body;
            const allRcpts = [...replyTo];
            if (replyCc.length > 0) allRcpts.push(...replyCc);

            const bin = await msmtpBin();
            const sendRes = await msmtpSend(bin, sendAccount, allRcpts, msg);
            if (sendRes.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "Reply send failed", error: sendRes.stderr.slice(0, 500), suggestion: "Check msmtp config and that Proton Bridge is running", context: { account: sendAccount, to: replyTo.join(", "), exitCode: sendRes.exitCode } });
            }

            return {
              status: "ok",
              message: `Replied to ${replyTo.join(", ")}${replyAll ? " (reply-all)" : ""} via ${sendAccount}`,
              data: { from: fromAddress, to: replyTo, cc: replyCc.length > 0 ? replyCc : undefined, subject, account: sendAccount, inReplyTo: originalMessageId, replyAll },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Reply failed", err, "Is msmtp installed and configured? Is Proton Bridge running?");
          }
        }

        // ── sync ─────────────────────────────────────────────────
        if (action === "sync") {
          try {
            const wait = (args.wait as boolean) ?? true;

            if (wait) {
              const result = await new Promise<{ exitCode: number; stdout: string; stderr: string }>((resolve) => {
                execFile(SYNC_MAIL, [], { timeout: 120000, maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
                  const code = error && "code" in error ? (error.code as number) : 0;
                  resolve({
                    exitCode: typeof code === "number" ? code : 1,
                    stdout: stdout?.toString() ?? "",
                    stderr: stderr?.toString() ?? "",
                  });
                });
              });

              if (result.exitCode !== 0) {
                return {
                  status: "partial",
                  message: `Sync completed with exit code ${result.exitCode} (partial failures are normal — Bridge rejects some messages)`,
                  data: { exitCode: result.exitCode, output: result.stdout.slice(-1000), errors: result.stderr.slice(-500) },
                };
              }
              return { status: "ok", message: "Sync complete", data: { output: result.stdout.slice(-500) } };
            } else {
              const proc = spawn(SYNC_MAIL, [], { detached: true, stdio: "ignore" });
              proc.unref();
              return { status: "ok", message: `Sync started (PID ${proc.pid})` };
            }
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Sync failed", err, "Is sync-mail script at ~/.local/bin/sync-mail? Is Proton Bridge running?");
          }
        }

        // ── accounts ─────────────────────────────────────────────
        if (action === "accounts") {
          return {
            status: "ok",
            message: `${ACCOUNTS.length} accounts configured`,
            data: {
              accounts: ACCOUNTS,
              savedSearches: Object.keys(SAVED_SEARCHES),
              categoryTags: CATEGORY_TAGS,
              flagTags: FLAG_TAGS,
            },
          };
        }

        // ── folders ──────────────────────────────────────────────
        if (action === "folders") {
          try {
            const account = args.folder_account as string | undefined;
            const baseDir = account ? join(MAILDIR, account) : MAILDIR;

            const folders: Array<{ path: string; name: string; count?: number }> = [];
            await walkMaildir(baseDir, MAILDIR, folders);

            try {
              const nm = await notmuchBin();
              for (const f of folders) {
                const res = await notmuchExec(nm, ["count", `folder:${f.name}`]);
                if (res.exitCode === 0) {
                  f.count = parseInt(res.stdout.trim(), 10) || 0;
                }
              }
            } catch {
              /* counts unavailable */
            }

            return { status: "ok", message: `${folders.length} folders`, data: folders };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Folder listing failed", err, "Check Maildir path exists at ~/400_mail/Maildir");
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
      },
    },
  ];
}
