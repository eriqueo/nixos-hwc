/**
 * Minimal CalDAV client + VTODO codec for the Radicale tasks backend
 * (tasks.hwc.iheartwoodcraft.com → domains/server/services/radicale).
 *
 * Uses fetch with Basic auth read from the radicale-htpasswd agenix secret
 * ("user:password", mounted on every host). Works identically from the
 * server (claude.ai gateway) and the laptop (Claude Code stdio gateway).
 *
 * Edits are property-surgical on the raw unfolded ICS so foreign properties
 * (Apple X-*, RRULE, VALARM blocks) survive untouched.
 */

import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";

const BASE_URL =
  process.env.HWC_TASKS_CALDAV_URL || "https://tasks.hwc.iheartwoodcraft.com";
const HTPASSWD_PATH =
  process.env.HWC_TASKS_HTPASSWD_PATH || "/run/agenix/radicale-htpasswd";

interface Credential {
  user: string;
  password: string;
}

let _cred: Credential | null = null;

async function credential(): Promise<Credential> {
  if (_cred) return _cred;
  const raw = await readFile(HTPASSWD_PATH, "utf-8");
  const line = raw.split("\n")[0].trim();
  const idx = line.indexOf(":");
  if (idx < 1) throw new Error(`malformed htpasswd at ${HTPASSWD_PATH}`);
  _cred = { user: line.slice(0, idx), password: line.slice(idx + 1) };
  return _cred;
}

export async function davRequest(
  method: string,
  path: string,
  opts: { body?: string; headers?: Record<string, string> } = {},
): Promise<{ status: number; body: string }> {
  const { user, password } = await credential();
  const url = `${BASE_URL.replace(/\/$/, "")}${path}`;
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Basic ${Buffer.from(`${user}:${password}`).toString("base64")}`,
      ...(opts.body ? { "Content-Type": "application/xml; charset=utf-8" } : {}),
      ...(opts.headers || {}),
    },
    body: opts.body,
  });
  return { status: res.status, body: await res.text() };
}

export async function davUser(): Promise<string> {
  return (await credential()).user;
}

/* ════════════════════════════════════════════════════════════════ */
/*  Collections (task lists)                                        */
/* ════════════════════════════════════════════════════════════════ */

export interface TaskList {
  href: string; // "/eric/<uuid>/"
  name: string; // displayname
}

const RESPONSE_RE = /<response>([\s\S]*?)<\/response>/g;

function xmlText(block: string, tag: string): string | null {
  const m = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`));
  return m ? m[1].trim() : null;
}

function xmlUnescape(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#13;/g, "\r")
    .replace(/&amp;/g, "&");
}

export async function listTaskLists(): Promise<TaskList[]> {
  const user = await davUser();
  const { status, body } = await davRequest("PROPFIND", `/${user}/`, {
    headers: { Depth: "1" },
    body:
      `<?xml version="1.0"?><propfind xmlns="DAV:">` +
      `<prop><displayname/><resourcetype/></prop></propfind>`,
  });
  if (status !== 207) throw new Error(`PROPFIND /${user}/ → HTTP ${status}`);

  const lists: TaskList[] = [];
  for (const m of body.matchAll(RESPONSE_RE)) {
    const block = m[1];
    const href = xmlText(block, "href");
    if (!href || href === `/${user}/` || !block.includes("<C:calendar")) continue;
    const name = xmlText(block, "displayname");
    lists.push({ href, name: name ? xmlUnescape(name) : href });
  }
  return lists.sort((a, b) => a.name.localeCompare(b.name));
}

export async function createTaskList(name: string): Promise<TaskList> {
  const user = await davUser();
  const href = `/${user}/${randomUUID().replace(/-/g, "").toUpperCase()}/`;
  const { status, body } = await davRequest("MKCALENDAR", href, {
    body:
      `<?xml version="1.0"?>` +
      `<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">` +
      `<D:set><D:prop><D:displayname>${escapeXml(name)}</D:displayname>` +
      `<C:supported-calendar-component-set><C:comp name="VTODO"/></C:supported-calendar-component-set>` +
      `</D:prop></D:set></C:mkcalendar>`,
  });
  if (status < 200 || status >= 300)
    throw new Error(`MKCALENDAR ${href} → HTTP ${status}: ${body.slice(0, 200)}`);
  return { href, name };
}

function escapeXml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/* ════════════════════════════════════════════════════════════════ */
/*  VTODO codec                                                     */
/* ════════════════════════════════════════════════════════════════ */

export interface Task {
  uid: string;
  href: string; // full item href
  list: string; // list displayname
  summary: string;
  status: string; // NEEDS-ACTION | IN-PROCESS | COMPLETED | CANCELLED
  priority: number; // 1 = highest … 9, 0 = none
  due: string | null; // YYYY-MM-DD (or full datetime string)
  categories: string[]; // keeps +project/@context sigils
  description: string;
  recurring: boolean;
}

/** Unfold RFC 5545 folded lines (CRLF or LF followed by space/tab). */
export function unfoldIcs(raw: string): string {
  return raw.replace(/\r?\n[ \t]/g, "");
}

function icsUnescape(s: string): string {
  return s
    .replace(/\\n/gi, "\n")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\\\/g, "\\");
}

function icsEscape(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

/** Extract "PROP" or "PROP;PARAMS" value from an unfolded VTODO body. */
function icsProp(body: string, prop: string): { params: string; value: string } | null {
  const m = body.match(new RegExp(`^${prop}((?:;[^:\\n]*)?):(.*)$`, "mi"));
  return m ? { params: m[1] || "", value: m[2].trim() } : null;
}

function formatDue(v: string): string {
  // 20260620 or 20260620T... → 2026-06-20 (keep time when present)
  const m = v.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2}))?/);
  if (!m) return v;
  const date = `${m[1]}-${m[2]}-${m[3]}`;
  return m[4] ? `${date} ${m[4]}:${m[5]}` : date;
}

export function parseVtodo(raw: string, href: string, list: string): Task | null {
  const unfolded = unfoldIcs(raw);
  const todoMatch = unfolded.match(/BEGIN:VTODO([\s\S]*?)END:VTODO/);
  if (!todoMatch) return null;
  const body = todoMatch[1];

  const uid = icsProp(body, "UID")?.value;
  if (!uid) return null;

  const catsRaw = icsProp(body, "CATEGORIES")?.value || "";
  const categories = catsRaw
    ? catsRaw.split(",").map((c) => icsUnescape(c.trim())).filter(Boolean)
    : [];

  const dueRaw = icsProp(body, "DUE")?.value || null;

  return {
    uid,
    href,
    list,
    summary: icsUnescape(icsProp(body, "SUMMARY")?.value || ""),
    status: (icsProp(body, "STATUS")?.value || "NEEDS-ACTION").toUpperCase(),
    priority: parseInt(icsProp(body, "PRIORITY")?.value || "0", 10) || 0,
    due: dueRaw ? formatDue(dueRaw) : null,
    categories,
    description: icsUnescape(icsProp(body, "DESCRIPTION")?.value || ""),
    recurring: /^RRULE[;:]/m.test(body),
  };
}

function utcStamp(): string {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/** Build a fresh VTODO ics document. due = "YYYY-MM-DD" (all-day). */
export function buildVtodo(fields: {
  uid: string;
  summary: string;
  categories?: string[];
  priority?: number;
  due?: string | null;
  description?: string;
}): string {
  const now = utcStamp();
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:hwc-mcp-tasks",
    "BEGIN:VTODO",
    `UID:${fields.uid}`,
    `DTSTAMP:${now}`,
    `CREATED:${now}`,
    `LAST-MODIFIED:${now}`,
    "SEQUENCE:1",
    "STATUS:NEEDS-ACTION",
    `SUMMARY:${icsEscape(fields.summary)}`,
  ];
  if (fields.categories?.length)
    lines.push(`CATEGORIES:${fields.categories.map(icsEscape).join(",")}`);
  if (fields.priority) lines.push(`PRIORITY:${fields.priority}`);
  if (fields.due) lines.push(`DUE;VALUE=DATE:${fields.due.replace(/-/g, "")}`);
  if (fields.description)
    lines.push(`DESCRIPTION:${icsEscape(fields.description)}`);
  lines.push("END:VTODO", "END:VCALENDAR");
  return lines.join("\r\n") + "\r\n";
}

/**
 * Surgical property edit on an existing ics: replaces (or inserts/removes)
 * the given properties inside the VTODO block, bumps SEQUENCE +
 * LAST-MODIFIED + DTSTAMP, leaves everything else (X-*, RRULE, alarms)
 * untouched. Value `null` removes the property; values are pre-formatted
 * full lines sans property name (e.g. {";VALUE=DATE:20260620"}).
 */
export function editVtodo(raw: string, props: Record<string, string | null>): string {
  let ics = unfoldIcs(raw);

  const todoMatch = ics.match(/BEGIN:VTODO[\s\S]*?END:VTODO/);
  if (!todoMatch) throw new Error("no VTODO component in document");
  let body = todoMatch[0];

  const all: Record<string, string | null> = {
    ...props,
    "LAST-MODIFIED": `:${utcStamp()}`,
    DTSTAMP: `:${utcStamp()}`,
  };

  // SEQUENCE bump
  const seqMatch = body.match(/^SEQUENCE(?:;[^:\n]*)?:(\d+)\s*$/m);
  all.SEQUENCE = `:${(seqMatch ? parseInt(seqMatch[1], 10) : 0) + 1}`;

  for (const [prop, rest] of Object.entries(all)) {
    const lineRe = new RegExp(`^${prop}(?:;[^:\\n]*)?:.*(?:\\r?\\n)`, "mi");
    if (rest === null) {
      body = body.replace(lineRe, "");
    } else if (lineRe.test(body)) {
      body = body.replace(lineRe, `${prop}${rest}\r\n`);
    } else {
      body = body.replace(/END:VTODO/, `${prop}${rest}\r\nEND:VTODO`);
    }
  }

  ics = ics.replace(/BEGIN:VTODO[\s\S]*?END:VTODO/, body);
  return ics;
}

/* ════════════════════════════════════════════════════════════════ */
/*  Item operations                                                 */
/* ════════════════════════════════════════════════════════════════ */

const CALDATA_RE =
  /<response>[\s\S]*?<href>([^<]+)<\/href>[\s\S]*?calendar-data[^>]*>([\s\S]*?)<\/(?:C:)?calendar-data>[\s\S]*?<\/response>/g;

export async function listTodosIn(list: TaskList): Promise<Task[]> {
  const { status, body } = await davRequest("REPORT", list.href, {
    headers: { Depth: "1" },
    body:
      `<?xml version="1.0"?>` +
      `<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">` +
      `<D:prop><C:calendar-data/></D:prop>` +
      `<C:filter><C:comp-filter name="VCALENDAR"><C:comp-filter name="VTODO"/></C:comp-filter></C:filter>` +
      `</C:calendar-query>`,
  });
  if (status !== 207) throw new Error(`REPORT ${list.href} → HTTP ${status}`);

  const tasks: Task[] = [];
  for (const m of body.matchAll(CALDATA_RE)) {
    const task = parseVtodo(xmlUnescape(m[2]), m[1], list.name);
    if (task) tasks.push(task);
  }
  return tasks;
}

export async function listAllTodos(): Promise<{ tasks: Task[]; lists: TaskList[] }> {
  const lists = await listTaskLists();
  const groups = await Promise.all(lists.map(listTodosIn));
  return { tasks: groups.flat(), lists };
}

export async function fetchRawItem(href: string): Promise<string> {
  const { status, body } = await davRequest("GET", href);
  if (status !== 200) throw new Error(`GET ${href} → HTTP ${status}`);
  return body;
}

export async function putItem(href: string, ics: string): Promise<void> {
  const { status, body } = await davRequest("PUT", href, {
    body: ics,
    headers: { "Content-Type": "text/calendar; charset=utf-8" },
  });
  if (status < 200 || status >= 300)
    throw new Error(`PUT ${href} → HTTP ${status}: ${body.slice(0, 200)}`);
}

export async function deleteItem(href: string): Promise<void> {
  const { status } = await davRequest("DELETE", href);
  if (status < 200 || status >= 300) throw new Error(`DELETE ${href} → HTTP ${status}`);
}
