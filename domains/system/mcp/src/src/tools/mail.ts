/**
 * hwc_mail_* tools — health, search, read, tag, actions, send, sync, accounts, folders.
 *
 * Health: consumes state files written by the real mail-health timer.
 * Mail ops: notmuch for search/read/count/tag, msmtp for send.
 * Tag system: category tags are mutually exclusive, flag tags are additive.
 *
 * Runs as a system service — notmuch/msmtp/sync-mail may not be in PATH.
 * Binary resolution tries PATH first, then /etc/profiles/per-user/eric/bin/.
 */

import { execFile, spawn } from "node:child_process";
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

/* ── Tag taxonomy (mirrors tags.nix — single source of truth) ── */

/** Category tags are mutually exclusive — assigning one removes all others. */
const CATEGORY_TAGS = [
  // Business (copper-orange)
  "office", "work", "hwcmt",
  // Money (blue)
  "finance", "bank", "insurance",
  // Personal (warm amber)
  "personal", "family", "eriqueokeefe",
  // Growth (sage green)
  "admin", "coaching",
  // System (muted gray)
  "tech", "aerc", "website",
];

/** Flag tags are additive — they coexist with categories. */
const FLAG_TAGS = ["action", "pending"];

/** Junk tags cleared by clear-categories action. */
const JUNK_TAGS = ["important", "flagged", "starred"];

/* ── Saved searches (mirrors searches.nix + aerc notmuch-queries) */

const SAVED_SEARCHES: Record<string, string> = {
  // Core views
  inbox: "tag:inbox AND NOT tag:trash",
  unread: "tag:unread AND NOT tag:trash",
  sent: "tag:sent",
  drafts: "tag:draft",
  archive: "tag:archive AND NOT tag:trash",
  trash: "tag:trash",
  spam: "tag:spam",
  important: "tag:important AND NOT tag:trash",
  // Flag views (inbox-scoped)
  action: "(tag:action AND NOT tag:trash) AND tag:inbox",
  pending: "(tag:pending AND NOT tag:trash) AND tag:inbox",
  // Category views (inbox-scoped)
  office: "(tag:office AND NOT tag:trash) AND tag:inbox",
  work: "(tag:work AND NOT tag:trash) AND tag:inbox",
  hwcmt: "(tag:hwcmt AND NOT tag:trash) AND tag:inbox",
  finance: "(tag:finance AND NOT tag:trash) AND tag:inbox",
  bank: "(tag:bank AND NOT tag:trash) AND tag:inbox",
  insurance: "(tag:insurance AND NOT tag:trash) AND tag:inbox",
  personal: "(tag:personal AND NOT tag:trash) AND tag:inbox",
  family: "(tag:family AND NOT tag:trash) AND tag:inbox",
  eriqueokeefe: "(tag:eriqueokeefe AND NOT tag:trash) AND tag:inbox",
  admin: "(tag:admin AND NOT tag:trash) AND tag:inbox",
  coaching: "(tag:coaching AND NOT tag:trash) AND tag:inbox",
  tech: "(tag:tech AND NOT tag:trash) AND tag:inbox",
  website: "(tag:website AND NOT tag:trash) AND tag:inbox",
  // Label views (all mail, not inbox-scoped)
  "label:work": "tag:work AND NOT tag:trash",
  "label:finance": "tag:finance AND NOT tag:trash",
  "label:coaching": "tag:coaching AND NOT tag:trash",
  "label:tech": "tag:tech AND NOT tag:trash",
  "label:bank": "tag:bank AND NOT tag:trash",
  "label:insurance": "tag:insurance AND NOT tag:trash",
  "label:personal": "tag:personal AND NOT tag:trash",
  "label:hwcmt": "tag:hwcmt AND NOT tag:trash",
  "label:hide": "tag:hide",
  // Unified / identity views
  unified: "tag:inbox",
  "inbox:hwc": "tag:inbox AND tag:hwc",
  "inbox:proton-hwc": "tag:inbox AND tag:proton-hwc",
  "inbox:proton-personal": "tag:inbox AND tag:proton-personal",
  "all:work": "tag:inbox AND tag:hwc",
  "all:personal": "tag:inbox AND tag:proton-personal",
};

/* ── Account definitions (mirrors accounts/index.nix) ─────────── */

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

/** msmtp account → from address for send tool. */
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

/**
 * Run notmuch via execFile (no shell) — safe from injection.
 * Unlike safeExec, allows parentheses in args (needed for notmuch queries).
 */
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

/** Pipe an RFC-822 message to msmtp via spawn. */
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

/** Resolve a query — if it matches a saved search name, expand it. */
function resolveQuery(query: string): string {
  return SAVED_SEARCHES[query] ?? query;
}

/** Build exclusive category tag ops: +category -all-other-categories. */
function exclusiveCategoryOps(category: string): string[] {
  const ops = [`+${category}`];
  for (const c of CATEGORY_TAGS) {
    if (c !== category) ops.push(`-${c}`);
  }
  return ops;
}

/** Build clear-all-custom tag ops: -all-categories -all-flags -junk. */
function clearAllCustomOps(): string[] {
  return [...CATEGORY_TAGS, ...FLAG_TAGS, ...JUNK_TAGS].map((t) => `-${t}`);
}

/* ── notmuch output parsers ────────────────────────────────────── */

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
        filename: m.filename,
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

/** Strip HTML tags for plain-text extraction. */
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
/*  Tool definitions                                               */
/* ════════════════════════════════════════════════════════════════ */

export function mailTools(): ToolDef[] {
  return [
    /* ── Health ──────────────────────────────────────────────── */
    {
      name: "hwc_mail_health",
      description:
        "Check mail system health. Returns Proton Bridge status, sync freshness, notmuch stats, " +
        "and health timer state (last-healthy, first-failure, cooldowns). " +
        "Use when diagnosing mail delivery or sync issues. Read-only.",
      inputSchema: { type: "object", properties: {} },
      handler: async (): Promise<ToolResult> => {
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
            const cooldowns = entries.filter((e) => e.startsWith("cooldown-"));
            if (cooldowns.length > 0) {
              result.activeCooldowns = await Promise.all(
                cooldowns.map(async (c) => {
                  const parts = c.replace("cooldown-", "").split("-");
                  const tsRaw = await readSafe(join(MAIL_HEALTH_STATE, c));
                  return {
                    level: parts[0],
                    fingerprint: parts.slice(1).join("-"),
                    sentAt: tsRaw ? new Date(parseInt(tsRaw, 10) * 1000).toISOString() : null,
                  };
                }),
              );
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
      },
    },

    /* ── Search ──────────────────────────────────────────────── */
    {
      name: "hwc_mail_search",
      description:
        "Search mail via notmuch. Accepts saved search names (inbox, unread, action, pending, " +
        "label:finance, all:personal, etc.) or raw notmuch queries (from:user@example.com, " +
        "date:2024..today). Returns thread summaries with subjects, authors, dates, tags. " +
        "Use for browsing mail or finding specific messages.",
      inputSchema: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description:
              "Notmuch query or saved search name (e.g. 'inbox', 'label:finance', 'from:github.com')",
          },
          limit: { type: "number", description: "Max results (default 20)" },
          offset: { type: "number", description: "Skip first N results" },
        },
        required: ["query"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const rawQuery = args.query as string;
          const query = resolveQuery(rawQuery);
          const wasResolved = query !== rawQuery;
          const limit = (args.limit as number) || 20;
          const offset = (args.offset as number) || 0;
          const nm = await notmuchBin();

          const res = await notmuchExec(
            nm,
            ["search", "--format=json", `--limit=${limit}`, `--offset=${offset}`, query],
            { timeout: 10000 },
          );
          if (res.exitCode !== 0) {
            return mcpError({ type: "COMMAND_FAILED", message: "notmuch search failed", error: res.stderr.slice(0, 500), suggestion: "Check query syntax. Use saved search names (inbox, action, label:finance) or raw notmuch queries.", context: { query, exitCode: res.exitCode } });
          }

          const threads = JSON.parse(res.stdout || "[]");
          const resolvedNote = wasResolved ? ` (resolved '${rawQuery}' → '${query}')` : "";
          return {
            status: "ok",
            message: `${threads.length} threads (offset ${offset}, limit ${limit})${resolvedNote}`,
            data: threads,
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Search failed", err, "Is notmuch installed and the Xapian database accessible?");
        }
      },
    },

    /* ── Read ────────────────────────────────────────────────── */
    {
      name: "hwc_mail_read",
      description:
        "Read a specific email thread or message. Pass a notmuch thread ID (thread:XXXX) or " +
        "message ID (id:msgid@host) from search results. Returns headers, body text, and HTML " +
        "(stripped to plain text). Set entireThread=true for full conversation.",
      inputSchema: {
        type: "object",
        properties: {
          id: {
            type: "string",
            description: "Thread or message ID (e.g. 'thread:000000000012ab' or 'id:msgid@host')",
          },
          entireThread: { type: "boolean", description: "Show entire thread (default false)" },
        },
        required: ["id"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const id = args.id as string;
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
      },
    },

    /* ── Count ───────────────────────────────────────────────── */
    {
      name: "hwc_mail_count",
      description:
        "Count messages matching a notmuch query or saved search name. Default: all messages.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Notmuch query or saved search name (default '*')" },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const rawQuery = (args.query as string) || "*";
          const query = resolveQuery(rawQuery);
          const nm = await notmuchBin();
          const res = await notmuchExec(nm, ["count", query]);
          if (res.exitCode !== 0) {
            return mcpError({ type: "COMMAND_FAILED", message: "notmuch count failed", error: res.stderr.slice(0, 300), suggestion: "Check query syntax", context: { query } });
          }
          const count = parseInt(res.stdout.trim(), 10) || 0;
          return { status: "ok", message: `${count} messages`, data: { count, query } };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Count failed", err);
        }
      },
    },

    /* ── Tag (raw + category/flag modes) ─────────────────────── */
    {
      name: "hwc_mail_tag",
      description:
        "Tag messages. Three modes: (1) Raw: tags=['+archive','-inbox']. " +
        "(2) Category: category='work' — exclusive, auto-removes other categories. " +
        "(3) Flag: flag='+action' — additive. SIDE EFFECT: modifies the Xapian database.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Notmuch query or saved search name" },
          tags: {
            type: "array",
            items: { type: "string" },
            description: "Raw tag ops: '+tag' to add, '-tag' to remove",
          },
          category: {
            type: "string",
            description: `Exclusive category: ${CATEGORY_TAGS.join(", ")}`,
          },
          flag: {
            type: "string",
            description: "Additive flag: '+action', '-action', '+pending', '-pending'",
          },
        },
        required: ["query"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const rawQuery = args.query as string;
          const query = resolveQuery(rawQuery);
          const rawTags = args.tags as string[] | undefined;
          const category = args.category as string | undefined;
          const flag = args.flag as string | undefined;

          // Determine tag operations
          let ops: string[];
          let mode: string;

          if (category) {
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
            return mcpError({ type: "VALIDATION_ERROR", message: "Specify tags, category, or flag.", suggestion: "Provide one of: tags (raw ops), category (exclusive), or flag (additive)" });
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
      },
    },

    /* ── Actions (high-level semantic operations) ────────────── */
    {
      name: "hwc_mail_actions",
      description:
        "High-level mail actions: archive, trash, untrash, spam, unspam, read, unread, " +
        "clear-categories. Each maps to the correct tag combination. " +
        "SIDE EFFECT: modifies the Xapian database.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Notmuch query or saved search name" },
          action: {
            type: "string",
            enum: ["archive", "trash", "untrash", "spam", "unspam", "read", "unread", "clear-categories"],
            description: "Action to perform",
          },
        },
        required: ["query", "action"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const rawQuery = args.query as string;
          const query = resolveQuery(rawQuery);
          const action = args.action as string;

          const actionMap: Record<string, string[]> = {
            archive: ["+archive", "-inbox"],
            trash: ["+trash", "-inbox", "-unread"],
            untrash: ["-trash", "+inbox"],
            spam: ["+spam", "-inbox", "-unread"],
            unspam: ["-spam", "+inbox"],
            read: ["-unread"],
            unread: ["+unread"],
            "clear-categories": clearAllCustomOps(),
          };

          const ops = actionMap[action];
          if (!ops) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Unknown action '${action}'. Valid: ${Object.keys(actionMap).join(", ")}`, suggestion: "Use one of the supported high-level actions" });
          }

          const nm = await notmuchBin();
          const res = await notmuchExec(nm, ["tag", ...ops, "--", query]);
          if (res.exitCode !== 0) {
            return mcpError({ type: "COMMAND_FAILED", message: `Action '${action}' failed`, error: res.stderr.slice(0, 500), suggestion: "Check query syntax and Xapian DB write permissions", context: { action, query, ops } });
          }
          return {
            status: "ok",
            message: `${action}: applied [${ops.join(", ")}] to: ${rawQuery}`,
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Action failed", err, "Check notmuch binary and Xapian DB write permissions");
        }
      },
    },

    /* ── Send ────────────────────────────────────────────────── */
    {
      name: "hwc_mail_send",
      description:
        "Send an email via msmtp. Default account: proton-hwc (eric@iheartwoodcraft.com). " +
        "Alternates: proton-personal, proton-office, gmail-personal, gmail-business. " +
        "Requires Proton Bridge for proton accounts. SIDE EFFECT: sends real email.",
      inputSchema: {
        type: "object",
        properties: {
          to: { type: "string", description: "Recipient(s), comma-separated" },
          subject: { type: "string", description: "Subject line" },
          body: { type: "string", description: "Plain text body" },
          from: { type: "string", description: "From address (auto-set from account)" },
          cc: { type: "string", description: "CC address(es)" },
          bcc: { type: "string", description: "BCC address(es)" },
          account: { type: "string", description: "msmtp account (default proton-hwc)" },
          inReplyTo: { type: "string", description: "Message-ID for threading (In-Reply-To header)" },
        },
        required: ["to", "subject", "body"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const to = args.to as string;
          const subject = args.subject as string;
          const body = args.body as string;
          const account = (args.account as string) || "proton-hwc";
          const cc = args.cc as string | undefined;
          const bcc = args.bcc as string | undefined;
          const inReplyTo = args.inReplyTo as string | undefined;
          const from = (args.from as string) || FROM_MAP[account] || FROM_MAP["proton-hwc"];

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
          const res = await msmtpSend(bin, account, rcpts, msg);
          if (res.exitCode !== 0) {
            return mcpError({ type: "COMMAND_FAILED", message: "Send failed", error: res.stderr.slice(0, 500), suggestion: "Check msmtp config, account name, and that Proton Bridge is running", context: { account, to, exitCode: res.exitCode } });
          }

          return {
            status: "ok",
            message: `Sent to ${to} via ${account}`,
            data: { from, to, cc, subject, account },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Send failed", err, "Is msmtp installed and configured? Is Proton Bridge running?");
        }
      },
    },

    /* ── Sync ────────────────────────────────────────────────── */
    {
      name: "hwc_mail_sync",
      description:
        "Trigger a full mail sync cycle: afew move → label copy-back → mbsync → notmuch new. " +
        "By default waits up to 2 min for completion. Set wait=false for fire-and-forget. " +
        "SIDE EFFECT: syncs with remote IMAP server.",
      inputSchema: {
        type: "object",
        properties: {
          wait: {
            type: "boolean",
            description: "Wait for sync to complete (default true, max 2 min)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const wait = (args.wait as boolean) ?? true;

          if (wait) {
            // Run sync-mail and wait for completion
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
                data: {
                  exitCode: result.exitCode,
                  output: result.stdout.slice(-1000),
                  errors: result.stderr.slice(-500),
                },
              };
            }

            return {
              status: "ok",
              message: "Sync complete",
              data: { output: result.stdout.slice(-500) },
            };
          } else {
            // Fire and forget
            const proc = spawn(SYNC_MAIL, [], { detached: true, stdio: "ignore" });
            proc.unref();
            return { status: "ok", message: `Sync started (PID ${proc.pid})` };
          }
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Sync failed", err, "Is sync-mail script at ~/.local/bin/sync-mail? Is Proton Bridge running?");
        }
      },
    },

    /* ── Accounts ─────────────────────────────────────────────── */
    {
      name: "hwc_mail_accounts",
      description:
        "List configured mail accounts with capabilities (sync, send, identities, msmtp account names).",
      inputSchema: { type: "object", properties: {} },
      handler: async (): Promise<ToolResult> => {
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
      },
    },

    /* ── Folders ──────────────────────────────────────────────── */
    {
      name: "hwc_mail_folders",
      description: "List Maildir folders with message counts.",
      inputSchema: {
        type: "object",
        properties: {
          account: { type: "string", description: "Filter to account (e.g. 'proton')" },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const account = args.account as string | undefined;
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
      },
    },
  ];
}
