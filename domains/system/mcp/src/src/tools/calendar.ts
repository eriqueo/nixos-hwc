/**
 * hwc_calendar — consolidated calendar tool (list, create, edit, delete, sync).
 */

import { execFile, spawn } from "node:child_process";
import { readdir, readFile, unlink } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { catchError, mcpError } from "../errors.js";
import { contract } from "../result.js";
import type { ResultEnvelope, ToolDef, ToolResult } from "../types.js";
import { log } from "../log.js";

/* ════════════════════════════════════════════════════════════════ */
/*  Binary resolution                                              */
/* ════════════════════════════════════════════════════════════════ */

// khalt supersedes plain khal. The MCP module (domains/system/mcp/index.nix)
// puts khalt's package on the service PATH and exports HWC_KHAL_BIN (the fork's
// `khal` binary) and HWC_KHALT_CONFIG (the isolated khalt config that points at
// the Radicale-synced calendars). We pass `-c <config>` so khal reads the same
// khalt config the TUI uses, rather than the legacy ~/.config/khal/config.
const KHAL_ENV_BIN = process.env.HWC_KHAL_BIN;
const KHALT_CONFIG = process.env.HWC_KHALT_CONFIG;
const KHAL_CANDIDATES = [
  ...(KHAL_ENV_BIN ? [KHAL_ENV_BIN] : []),
  "khal",
  "/etc/profiles/per-user/eric/bin/khal",
];
const VDIRSYNCER_CANDIDATES = ["vdirsyncer", "/etc/profiles/per-user/eric/bin/vdirsyncer"];
let _khal: string | null = null;
let _vdirsyncer: string | null = null;

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
    } catch { continue; }
  }
  throw new Error(`Binary not found: ${candidates.join(", ")}`);
}

async function khalBin(): Promise<string> {
  if (!_khal) _khal = await resolveBin(KHAL_CANDIDATES);
  return _khal;
}
async function vdirsyncerBin(): Promise<string> {
  if (!_vdirsyncer) _vdirsyncer = await resolveBin(VDIRSYNCER_CANDIDATES);
  return _vdirsyncer;
}

// Global `-c <config>` flag prepended to every khal invocation so the fork
// reads the khalt config (Radicale calendars). Empty when unset → khal's
// default config resolution applies.
function khalConfigArgs(): string[] {
  return KHALT_CONFIG ? ["-c", KHALT_CONFIG] : [];
}

/* ════════════════════════════════════════════════════════════════ */
/*  Executor                                                       */
/* ════════════════════════════════════════════════════════════════ */

function runBin(
  bin: string,
  args: string[],
  opts: { timeout?: number } = {},
): Promise<{ exitCode: number; stdout: string; stderr: string }> {
  const { timeout = 15000 } = opts;
  return new Promise((resolve) => {
    execFile(bin, args, { timeout, maxBuffer: 2 * 1024 * 1024 }, (err, stdout, stderr) => {
      resolve({ exitCode: err ? 1 : 0, stdout: stdout || "", stderr: stderr || "" });
    });
  });
}

/* ════════════════════════════════════════════════════════════════ */
/*  Parser                                                         */
/* ════════════════════════════════════════════════════════════════ */

interface CalendarEvent {
  date: string;
  startTime: string | null;
  endTime: string | null;
  summary: string;
  location: string | null;
  allDay: boolean;
}

/**
 * Universal Result Contract view (list) for a set of calendar events. id is
 * synthesized (date+time+summary — khal exposes no stable UID via --format);
 * label=summary, time=startTime or "all-day"; date/location ride the data bag.
 */
function eventsToView(
  events: CalendarEvent[],
  title: string,
  meta: Record<string, unknown>,
): ResultEnvelope {
  return contract("list", title, {
    items: events.map((e) => ({
      kind: "event",
      id: `${e.date}|${e.startTime ?? "all-day"}|${e.summary}`,
      label: e.summary,
      time: e.allDay ? "all-day" : (e.startTime ?? ""),
      date: e.date,
      ...(e.location ? { location: e.location } : {}),
    })),
  }, { ...meta, source: "hwc_calendar" });
}

const DAY_HEADER_RE = /^.+,\s+(\d{4}-\d{2}-\d{2})\s+\w+\s*$/;

function parseKhalOutput(raw: string): CalendarEvent[] {
  const events: CalendarEvent[] = [];
  let currentDate = "";

  for (const rawLine of raw.split("\n")) {
    const line = rawLine.trim();
    if (!line) continue;

    const headerMatch = line.match(DAY_HEADER_RE);
    if (headerMatch) {
      currentDate = headerMatch[1];
      continue;
    }

    if (!currentDate) continue;

    const parts = line.split("|");
    if (parts.length < 3) continue;

    const [startTime, endTime, title, location] = parts;
    if (!title || !title.trim()) continue;

    const allDay = !startTime || startTime.trim() === "";

    events.push({
      date: currentDate,
      startTime: allDay ? null : startTime.trim(),
      endTime: allDay ? null : (endTime || "").trim() || null,
      summary: title.trim(),
      location: location && location.trim() ? location.trim() : null,
      allDay,
    });
  }

  return events;
}

export async function khalList(start: string, end: string): Promise<CalendarEvent[]> {
  const bin = await khalBin();
  const { stdout, stderr, exitCode } = await runBin(bin, [
    ...khalConfigArgs(),
    "list",
    "--format", "{start-time}|{end-time}|{title}|{location}",
    start,
    end,
  ]);
  if (exitCode !== 0 && stderr) {
    log.warn("khal list failed", { stderr, exitCode });
  }
  return parseKhalOutput(stdout);
}

/* ════════════════════════════════════════════════════════════════ */
/*  Calendar storage helpers                                       */
/* ════════════════════════════════════════════════════════════════ */

const HOME = homedir();
// Both the legacy iCloud calendars dir and the Radicale-synced calendars dir
// (calendars-radicale/, written by the calendar_radicale vdirsyncer pair).
// delete/edit scan whichever exist.
const VDIRSYNCER_CALENDAR_ROOTS = [
  join(HOME, ".local/share/vdirsyncer/calendars"),
  join(HOME, ".local/share/vdirsyncer/calendars-radicale"),
];

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^\d{2}:\d{2}$/;

interface IcsEvent {
  path: string;
  uid: string;
  summary: string;
  dtstart: string | null;
  dtend: string | null;
  location: string | null;
  description: string | null;
}

function icsField(content: string, field: string): string | null {
  const regex = new RegExp(`^${field}[^:]*:(.+)$`, "mi");
  const match = content.match(regex);
  return match ? match[1].trim() : null;
}

// Recursively collect every *.ics path under a root (≤3 levels deep). iCloud
// stores at calendars/<account>/<collection>/*.ics (2 levels) while Radicale
// stores at calendars-radicale/<collection>/*.ics (1 level), so a recursive
// walk handles both layouts uniformly.
async function collectIcsPaths(dir: string, depth = 0): Promise<string[]> {
  if (depth > 3) return [];
  const out: string[] = [];
  let entries: string[];
  try {
    entries = await readdir(dir);
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = join(dir, entry);
    if (entry.endsWith(".ics")) {
      out.push(full);
    } else if (!entry.startsWith(".")) {
      out.push(...(await collectIcsPaths(full, depth + 1)));
    }
  }
  return out;
}

async function searchIcsFiles(query: string, dateFilter?: string): Promise<IcsEvent[]> {
  const results: IcsEvent[] = [];
  const lowerQuery = query.toLowerCase();

  const icsPaths: string[] = [];
  for (const root of VDIRSYNCER_CALENDAR_ROOTS) {
    icsPaths.push(...(await collectIcsPaths(root)));
  }
  if (icsPaths.length === 0) {
    log.warn("No .ics files found under vdirsyncer calendar roots");
  }

  for (const icsPath of icsPaths) {
    try {
      const content = await readFile(icsPath, "utf-8");
      const summary = icsField(content, "SUMMARY");
      const dtstart = icsField(content, "DTSTART");
      const uid = icsField(content, "UID");

      if (!summary || !uid) continue;
      if (!summary.toLowerCase().includes(lowerQuery)) continue;

      if (dateFilter && dtstart) {
        const eventDate = dtstart.substring(0, 10).replace(/(\d{4})(\d{2})(\d{2})/, "$1-$2-$3");
        if (!eventDate.startsWith(dateFilter)) continue;
      }

      results.push({
        path: icsPath,
        uid,
        summary,
        dtstart,
        dtend: icsField(content, "DTEND"),
        location: icsField(content, "LOCATION"),
        description: icsField(content, "DESCRIPTION"),
      });
    } catch { /* file not readable */ }
  }

  return results;
}

async function triggerSync(): Promise<void> {
  try {
    const bin = await vdirsyncerBin();
    const proc = spawn(bin, ["sync"], { detached: true, stdio: "ignore" });
    proc.unref();
    log.debug("Triggered vdirsyncer sync (fire-and-forget)");
  } catch (err) {
    log.warn("Failed to trigger vdirsyncer sync", { error: err });
  }
}

/* ════════════════════════════════════════════════════════════════ */
/*  Consolidated tool                                              */
/* ════════════════════════════════════════════════════════════════ */

export function calendarTools(): ToolDef[] {
  return [
    {
      name: "hwc_calendar",
      description: "Calendar management. Actions: list, create, edit, delete, sync.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["list", "create", "edit", "delete", "sync"],
            description: "Action to perform",
          },
          // [list] params
          range: {
            type: "string",
            enum: ["today", "week", "custom"],
            description: "[list] Preset range or 'custom' for start/end dates (default: today)",
          },
          start: { type: "string", description: "[list/create] Start date YYYY-MM-DD" },
          end: { type: "string", description: "[list] End date YYYY-MM-DD (defaults to start)" },
          timezone: { type: "string", description: "[list] IANA timezone (default: America/Denver)" },
          // [create] params
          summary: { type: "string", description: "[create/edit] Event title" },
          date: { type: "string", description: "[create] Start date YYYY-MM-DD (required)" },
          startTime: { type: "string", description: "[create/edit] Start time HH:MM (omit for all-day)" },
          endTime: { type: "string", description: "[create/edit] End time HH:MM" },
          endDate: { type: "string", description: "[create] End date YYYY-MM-DD for multi-day all-day" },
          calendar: { type: "string", description: "[create] khal calendar name (omit = default)" },
          location: { type: "string", description: "[create/edit] Event location" },
          description: { type: "string", description: "[create/edit] Event description" },
          // [delete/edit] params
          query: { type: "string", description: "[delete/edit] Search text to find the event" },
          filter_date: { type: "string", description: "[delete/edit] YYYY-MM-DD to narrow search" },
          confirm: { type: "boolean", description: "[delete/edit] If true, apply; if false (default), preview" },
          // [edit] params
          newSummary: { type: "string", description: "[edit] New event title" },
          newDate: { type: "string", description: "[edit] New date YYYY-MM-DD" },
          newStartTime: { type: "string", description: "[edit] New start time HH:MM" },
          newEndTime: { type: "string", description: "[edit] New end time HH:MM" },
          newLocation: { type: "string", description: "[edit] New location" },
          newDescription: { type: "string", description: "[edit] New description" },
        },
        required: ["action"],
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        const action = args.action as string;

        // ── list ─────────────────────────────────────────────────
        if (action === "list") {
          try {
            const range = (args.range as string) || "today";
            const tz = (args.timezone as string) || "America/Denver";

            if (range === "today") {
              const dateStr = new Date().toLocaleDateString("en-CA", { timeZone: tz });
              const events = await khalList(dateStr, dateStr);
              return {
                status: "ok",
                message: `${events.length} event${events.length !== 1 ? "s" : ""} on ${dateStr}`,
                data: { range: "today", date: dateStr, timezone: tz, event_count: events.length, events },
                view: eventsToView(events, "Today", { range: "today", date: dateStr, timezone: tz, event_count: events.length }),
              };
            }

            if (range === "week") {
              const bin = await khalBin();
              const { stdout, stderr, exitCode } = await runBin(bin, [
                ...khalConfigArgs(),
                "list",
                "--format", "{start-time}|{end-time}|{title}|{location}",
                "today",
                "week",
              ]);
              if (exitCode !== 0 && stderr) log.warn("khal list week failed", { stderr });
              const events = parseKhalOutput(stdout);
              const byDate: Record<string, CalendarEvent[]> = {};
              for (const ev of events) {
                if (!byDate[ev.date]) byDate[ev.date] = [];
                byDate[ev.date].push(ev);
              }
              return {
                status: "ok",
                message: `${events.length} event${events.length !== 1 ? "s" : ""} this week`,
                data: { range: "week", timezone: tz, event_count: events.length, by_date: byDate, events },
                view: eventsToView(events, "This Week", { range: "week", timezone: tz, event_count: events.length }),
              };
            }

            // custom range
            const start = args.start as string;
            const end = (args.end as string) || start;
            if (!start || !DATE_RE.test(start) || !DATE_RE.test(end)) {
              return mcpError({ type: "VALIDATION_ERROR", message: "Custom range requires start date in YYYY-MM-DD format", suggestion: "Provide start (and optionally end) as YYYY-MM-DD" });
            }
            const events = await khalList(start, end);
            return {
              status: "ok",
              message: `${events.length} event${events.length !== 1 ? "s" : ""} from ${start} to ${end}`,
              data: { range: "custom", start, end, event_count: events.length, events },
              view: eventsToView(events, `${start} – ${end}`, { range: "custom", start, end, event_count: events.length }),
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to list calendar events", err, "Check that khal is installed and vdirsyncer has synced at least once");
          }
        }

        // ── sync ─────────────────────────────────────────────────
        if (action === "sync") {
          try {
            const bin = await vdirsyncerBin();
            const { exitCode, stdout, stderr } = await runBin(bin, ["sync"], { timeout: 30000 });
            if (exitCode !== 0) {
              return { status: "error", message: "vdirsyncer sync failed", error: stderr.trim() || "non-zero exit code", error_type: "COMMAND_FAILED" };
            }
            return { status: "ok", message: "Calendar sync complete", data: { stdout: stdout.trim() || null } };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to run vdirsyncer sync", err, "Check vdirsyncer is installed and iCloud credentials are configured");
          }
        }

        // ── create ───────────────────────────────────────────────
        if (action === "create") {
          try {
            const summary = args.summary as string;
            const date = args.date as string;
            if (!summary || !date) {
              return mcpError({ type: "VALIDATION_ERROR", message: "summary and date are required for action=create" });
            }
            const startTime = args.startTime as string | undefined;
            const endTime = args.endTime as string | undefined;
            const endDate = args.endDate as string | undefined;
            const calendar = args.calendar as string | undefined;
            const location = args.location as string | undefined;
            const description = args.description as string | undefined;

            if (!DATE_RE.test(date)) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid date format: ${date}. Use YYYY-MM-DD.` });
            }
            if (endDate && !DATE_RE.test(endDate)) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid endDate format: ${endDate}. Use YYYY-MM-DD.` });
            }
            if (startTime && !TIME_RE.test(startTime)) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid startTime format: ${startTime}. Use HH:MM.` });
            }
            if (endTime && !TIME_RE.test(endTime)) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid endTime format: ${endTime}. Use HH:MM.` });
            }

            const khalArgs: string[] = [...khalConfigArgs(), "new"];
            if (calendar) khalArgs.push("-a", calendar);

            if (startTime) {
              const end = endTime || (() => {
                const [h, m] = startTime.split(":").map(Number);
                const endH = (h + 1) % 24;
                return `${String(endH).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
              })();
              khalArgs.push(date, startTime, end, summary);
            } else if (endDate) {
              khalArgs.push(date, endDate, summary);
            } else {
              khalArgs.push(date, summary);
            }

            if (location) khalArgs.push("--location", location);
            if (description) khalArgs.push("::", description);

            const bin = await khalBin();
            log.debug("khal new", { args: khalArgs });
            const { exitCode, stdout, stderr } = await runBin(bin, khalArgs, { timeout: 10000 });

            if (exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "Failed to create calendar event", error: stderr.trim() || stdout.trim() || "khal returned non-zero", suggestion: "Check that the date/time format is correct and khal is properly configured", context: { date, startTime, endTime, summary } });
            }

            await triggerSync();

            return {
              status: "ok",
              message: `Created event: "${summary}" on ${date}${startTime ? ` at ${startTime}` : " (all-day)"}`,
              data: { summary, date, startTime: startTime || null, endTime: endTime || null, endDate: endDate || null, location: location || null, description: description || null, calendar: calendar || "default", syncTriggered: true },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to create calendar event", err, "Check that khal is installed and calendar storage is accessible");
          }
        }

        // ── delete ───────────────────────────────────────────────
        if (action === "delete") {
          try {
            const query = args.query as string;
            if (!query) {
              return mcpError({ type: "VALIDATION_ERROR", message: "query is required for action=delete" });
            }
            const date = args.filter_date as string | undefined;
            const confirm = (args.confirm as boolean) ?? false;

            if (date && !DATE_RE.test(date)) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid date format: ${date}. Use YYYY-MM-DD.` });
            }

            const matches = await searchIcsFiles(query, date);

            if (matches.length === 0) {
              return { status: "ok", message: `No events found matching "${query}"${date ? ` on ${date}` : ""}`, data: { matches: [], matchCount: 0 } };
            }

            if (!confirm) {
              return {
                status: "ok",
                message: `Found ${matches.length} event(s) matching "${query}". Set confirm=true to delete.`,
                data: { matches: matches.map((m) => ({ summary: m.summary, dtstart: m.dtstart, location: m.location, uid: m.uid })), matchCount: matches.length, action: "dry-run" },
              };
            }

            if (matches.length > 1) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Multiple events (${matches.length}) match "${query}". Narrow the search or specify a date.`, suggestion: "Add a date filter or use a more specific query to match exactly one event", context: { matches: matches.map((m) => ({ summary: m.summary, dtstart: m.dtstart })) } });
            }

            const event = matches[0];
            await unlink(event.path);
            log.debug("Deleted .ics file", { path: event.path, summary: event.summary });
            await triggerSync();

            return {
              status: "ok",
              message: `Deleted event: "${event.summary}"`,
              data: { deleted: { summary: event.summary, dtstart: event.dtstart, uid: event.uid }, syncTriggered: true },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to delete calendar event", err, "Check that vdirsyncer calendar storage is accessible");
          }
        }

        // ── edit ─────────────────────────────────────────────────
        if (action === "edit") {
          try {
            const query = args.query as string;
            if (!query) {
              return mcpError({ type: "VALIDATION_ERROR", message: "query is required for action=edit" });
            }
            const date = args.filter_date as string | undefined;
            const newSummary = args.newSummary as string | undefined;
            const newDate = args.newDate as string | undefined;
            const newStartTime = args.newStartTime as string | undefined;
            const newEndTime = args.newEndTime as string | undefined;
            const newLocation = args.newLocation as string | undefined;
            const newDescription = args.newDescription as string | undefined;
            const confirm = (args.confirm as boolean) ?? false;

            if (date && !DATE_RE.test(date)) return mcpError({ type: "VALIDATION_ERROR", message: `Invalid date format: ${date}. Use YYYY-MM-DD.` });
            if (newDate && !DATE_RE.test(newDate)) return mcpError({ type: "VALIDATION_ERROR", message: `Invalid newDate format: ${newDate}. Use YYYY-MM-DD.` });
            if (newStartTime && !TIME_RE.test(newStartTime)) return mcpError({ type: "VALIDATION_ERROR", message: `Invalid newStartTime format: ${newStartTime}. Use HH:MM.` });
            if (newEndTime && !TIME_RE.test(newEndTime)) return mcpError({ type: "VALIDATION_ERROR", message: `Invalid newEndTime format: ${newEndTime}. Use HH:MM.` });

            const matches = await searchIcsFiles(query, date);

            if (matches.length === 0) {
              return { status: "ok", message: `No events found matching "${query}"${date ? ` on ${date}` : ""}`, data: { matches: [], matchCount: 0 } };
            }

            if (matches.length > 1) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Multiple events (${matches.length}) match "${query}". Narrow the search.`, suggestion: "Add a date filter or use a more specific query", context: { matches: matches.map((m) => ({ summary: m.summary, dtstart: m.dtstart })) } });
            }

            const event = matches[0];

            const existingDate = event.dtstart
              ? event.dtstart.substring(0, 8).replace(/(\d{4})(\d{2})(\d{2})/, "$1-$2-$3")
              : null;
            const existingStartTime = event.dtstart?.includes("T")
              ? event.dtstart.substring(9, 11) + ":" + event.dtstart.substring(11, 13)
              : null;
            const existingEndTime = event.dtend?.includes("T")
              ? event.dtend.substring(9, 11) + ":" + event.dtend.substring(11, 13)
              : null;

            const finalSummary = newSummary ?? event.summary;
            const finalDate = newDate ?? existingDate;
            const finalStartTime = newStartTime ?? existingStartTime;
            const finalEndTime = newEndTime ?? existingEndTime;
            const finalLocation = newLocation ?? event.location;
            const finalDescription = newDescription ?? event.description;

            if (!finalDate) {
              return mcpError({ type: "VALIDATION_ERROR", message: "Could not determine event date. Provide newDate." });
            }

            const changes = {
              summary: { from: event.summary, to: finalSummary },
              date: { from: existingDate, to: finalDate },
              startTime: { from: existingStartTime, to: finalStartTime },
              endTime: { from: existingEndTime, to: finalEndTime },
              location: { from: event.location, to: finalLocation },
              description: { from: event.description, to: finalDescription },
            };

            if (!confirm) {
              return {
                status: "ok",
                message: `Preview changes for "${event.summary}". Set confirm=true to apply.`,
                data: { original: { summary: event.summary, dtstart: event.dtstart, location: event.location }, changes, action: "dry-run" },
              };
            }

            await unlink(event.path);
            log.debug("Deleted old .ics for edit", { path: event.path });

            const khalArgs: string[] = [...khalConfigArgs(), "new"];
            if (finalStartTime) {
              const end = finalEndTime || (() => {
                const [h, m] = finalStartTime.split(":").map(Number);
                const endH = (h + 1) % 24;
                return `${String(endH).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
              })();
              khalArgs.push(finalDate, finalStartTime, end, finalSummary);
            } else {
              khalArgs.push(finalDate, finalSummary);
            }

            if (finalLocation) khalArgs.push("--location", finalLocation);
            if (finalDescription) khalArgs.push("::", finalDescription);

            const bin = await khalBin();
            const { exitCode, stderr } = await runBin(bin, khalArgs, { timeout: 10000 });

            if (exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: "Deleted old event but failed to create updated event", error: stderr.trim(), suggestion: "Use hwc_calendar action=create to manually recreate the event", context: { original: event.summary, changes } });
            }

            await triggerSync();

            return {
              status: "ok",
              message: `Updated event: "${event.summary}" → "${finalSummary}"`,
              data: { changes, syncTriggered: true },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to edit calendar event", err, "Check that vdirsyncer calendar storage is accessible");
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
      },
    },
  ];
}
