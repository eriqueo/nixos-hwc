/**
 * hwc_calendar_* tools — khal/vdirsyncer iCloud calendar access.
 *
 * Replaces Google Calendar MCP for the morning briefing.
 * khal 0.13.0 on NixOS, reading ~/.local/share/vdirsyncer/calendars/
 * vdirsyncer syncs from iCloud CalDAV every 15 minutes.
 *
 * khal 0.13 quirks:
 *   - --json flag is broken (returns empty arrays)
 *   - {start-date-short} token crashes — not supported
 *   - Day headers always appear even with --day-format ""
 *   - Valid format tokens: {start-time} {end-time} {title} {location} {calendar}
 *   - Day header line format: "Dayname, YYYY-MM-DD Dayname"
 *   - Event line format (with --format): pipe-delimited per our template
 *   - ANSI color codes present if {calendar-color}/{reset} used — avoid them
 */

import { execFile, spawn } from "node:child_process";
import { readdir, readFile, unlink } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { catchError, mcpError } from "../errors.js";
import type { ToolDef, ToolResult } from "../types.js";
import { log } from "../log.js";

/* ════════════════════════════════════════════════════════════════ */
/*  Binary resolution                                              */
/* ════════════════════════════════════════════════════════════════ */

const KHAL_CANDIDATES = ["khal", "/etc/profiles/per-user/eric/bin/khal"];
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
  date: string;           // YYYY-MM-DD from day header
  startTime: string | null;
  endTime: string | null;
  summary: string;
  location: string | null;
  allDay: boolean;
}

// Matches: "Tomorrow, 2026-04-08 Wednesday" or "Today, 2026-04-07 Tuesday"
const DAY_HEADER_RE = /^.+,\s+(\d{4}-\d{2}-\d{2})\s+\w+\s*$/;

function parseKhalOutput(raw: string): CalendarEvent[] {
  const events: CalendarEvent[] = [];
  let currentDate = "";

  for (const rawLine of raw.split("\n")) {
    const line = rawLine.trim();
    if (!line) continue;

    // Day header line — extract the date
    const headerMatch = line.match(DAY_HEADER_RE);
    if (headerMatch) {
      currentDate = headerMatch[1];
      continue;
    }

    if (!currentDate) continue;

    // Event line: "{start-time}|{end-time}|{title}|{location}"
    const parts = line.split("|");
    if (parts.length < 3) continue;

    const [startTime, endTime, title, location] = parts;
    if (!title || !title.trim()) continue;

    // All-day events have empty start-time in khal
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

async function khalList(start: string, end: string): Promise<CalendarEvent[]> {
  const bin = await khalBin();
  const { stdout, stderr, exitCode } = await runBin(bin, [
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
const VDIRSYNCER_CALENDARS = join(HOME, ".local/share/vdirsyncer/calendars");

/** Date format validation */
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

/** Parse a simple field from .ics content */
function icsField(content: string, field: string): string | null {
  const regex = new RegExp(`^${field}[^:]*:(.+)$`, "mi");
  const match = content.match(regex);
  return match ? match[1].trim() : null;
}

/** Search .ics files for events matching a query */
async function searchIcsFiles(query: string, dateFilter?: string): Promise<IcsEvent[]> {
  const results: IcsEvent[] = [];
  const lowerQuery = query.toLowerCase();

  try {
    const calDirs = await readdir(VDIRSYNCER_CALENDARS);

    for (const calDir of calDirs) {
      const calPath = join(VDIRSYNCER_CALENDARS, calDir);
      try {
        const subDirs = await readdir(calPath);

        for (const subDir of subDirs) {
          const subPath = join(calPath, subDir);
          try {
            const files = await readdir(subPath);

            for (const file of files) {
              if (!file.endsWith(".ics")) continue;

              const icsPath = join(subPath, file);
              try {
                const content = await readFile(icsPath, "utf-8");
                const summary = icsField(content, "SUMMARY");
                const dtstart = icsField(content, "DTSTART");
                const uid = icsField(content, "UID");

                if (!summary || !uid) continue;

                // Filter by query (case-insensitive summary match)
                if (!summary.toLowerCase().includes(lowerQuery)) continue;

                // Filter by date if provided
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
          } catch { /* subdir not readable */ }
        }
      } catch { /* calendar dir not readable */ }
    }
  } catch {
    log.warn("Failed to read vdirsyncer calendars directory");
  }

  return results;
}

/** Fire-and-forget vdirsyncer sync (non-blocking) */
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
/*  Tool definitions                                               */
/* ════════════════════════════════════════════════════════════════ */

export function calendarTools(): ToolDef[] {
  return [

    /* ── Today ───────────────────────────────────────────────────── */
    {
      name: "hwc_calendar_today",
      description:
        "Get today's calendar events from iCloud via khal (local sync, no network call). " +
        "vdirsyncer syncs from iCloud every 15 minutes automatically. " +
        "Always returns exactly today's events in America/Denver timezone. " +
        "Use this instead of Google Calendar MCP — faster, more reliable, correct date.",
      inputSchema: {
        type: "object",
        properties: {
          timezone: {
            type: "string",
            description: "IANA timezone for today's date (default: America/Denver)",
          },
        },
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        try {
          const tz = (args.timezone as string) || "America/Denver";
          const dateStr = new Date().toLocaleDateString("en-CA", { timeZone: tz });
          const events = await khalList(dateStr, dateStr);
          return {
            status: "ok",
            message: `${events.length} event${events.length !== 1 ? "s" : ""} on ${dateStr}`,
            data: { date: dateStr, timezone: tz, event_count: events.length, events },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to get today's calendar events", err,
            "Check that khal is installed and vdirsyncer has synced at least once");
        }
      },
    },

    /* ── Week ────────────────────────────────────────────────────── */
    {
      name: "hwc_calendar_week",
      description:
        "Get this week's calendar events from iCloud via khal (today through end of week). " +
        "Returns events grouped by date across all synced calendars. " +
        "Use for the morning briefing weekly overview and the dashboard week view.",
      inputSchema: {
        type: "object",
        properties: {
          timezone: {
            type: "string",
            description: "IANA timezone (default: America/Denver)",
          },
        },
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        try {
          const tz = (args.timezone as string) || "America/Denver";
          const bin = await khalBin();

          // "week" keyword shows the full week containing today in khal 0.13
          const { stdout, stderr, exitCode } = await runBin(bin, [
            "list",
            "--format", "{start-time}|{end-time}|{title}|{location}",
            "today",
            "week",
          ]);

          if (exitCode !== 0 && stderr) {
            log.warn("khal list week failed", { stderr });
          }

          const events = parseKhalOutput(stdout);

          // Group by date for dashboard rendering
          const byDate: Record<string, CalendarEvent[]> = {};
          for (const ev of events) {
            if (!byDate[ev.date]) byDate[ev.date] = [];
            byDate[ev.date].push(ev);
          }

          return {
            status: "ok",
            message: `${events.length} event${events.length !== 1 ? "s" : ""} this week`,
            data: { timezone: tz, event_count: events.length, by_date: byDate, events },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to get week's calendar events", err,
            "Check that khal is installed and vdirsyncer has synced at least once");
        }
      },
    },

    /* ── Date range ──────────────────────────────────────────────── */
    {
      name: "hwc_calendar_list",
      description:
        "Get calendar events for a specific date range from iCloud via khal. " +
        "Pass start and end as YYYY-MM-DD.",
      inputSchema: {
        type: "object",
        properties: {
          start: { type: "string", description: "Start date YYYY-MM-DD (inclusive)" },
          end: { type: "string", description: "End date YYYY-MM-DD (inclusive, defaults to start)" },
        },
        required: ["start"],
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        try {
          const start = args.start as string;
          const end = (args.end as string) || start;
          if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || !/^\d{4}-\d{2}-\d{2}$/.test(end)) {
            return {
              status: "error",
              message: "Invalid date format",
              error: "Use YYYY-MM-DD format for start and end dates",
              error_type: "VALIDATION_ERROR",
            };
          }
          const events = await khalList(start, end);
          return {
            status: "ok",
            message: `${events.length} event${events.length !== 1 ? "s" : ""} from ${start} to ${end}`,
            data: { start, end, event_count: events.length, events },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to list calendar events", err,
            "Check khal is installed and dates are valid YYYY-MM-DD");
        }
      },
    },

    /* ── Sync trigger ────────────────────────────────────────────── */
    {
      name: "hwc_calendar_sync",
      description:
        "Trigger an immediate vdirsyncer sync to pull latest events from iCloud. " +
        "Normally runs automatically every 15 minutes. Takes 5-15 seconds.",
      inputSchema: { type: "object", properties: {} },
      handler: async (): Promise<ToolResult> => {
        try {
          const bin = await vdirsyncerBin();
          const { exitCode, stdout, stderr } = await runBin(bin, ["sync"], { timeout: 30000 });
          if (exitCode !== 0) {
            return {
              status: "error",
              message: "vdirsyncer sync failed",
              error: stderr.trim() || "non-zero exit code",
              error_type: "COMMAND_FAILED",
            };
          }
          return {
            status: "ok",
            message: "Calendar sync complete",
            data: { stdout: stdout.trim() || null },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to run vdirsyncer sync", err,
            "Check vdirsyncer is installed and iCloud credentials are configured");
        }
      },
    },

    /* ── Create event ───────────────────────────────────────────── */
    {
      name: "hwc_calendar_create",
      description:
        "Create a new iCloud calendar event via khal. Supports timed events (date + startTime + endTime), " +
        "all-day events (date only), and multi-day all-day events (date + endDate). After creation, " +
        "triggers a vdirsyncer sync to push the event to iCloud. SIDE EFFECT: creates a real calendar event " +
        "and syncs to iCloud.",
      inputSchema: {
        type: "object",
        properties: {
          summary: { type: "string", description: "Event title (required)" },
          date: { type: "string", description: "Start date YYYY-MM-DD (required)" },
          startTime: { type: "string", description: "Start time HH:MM (omit for all-day event)" },
          endTime: { type: "string", description: "End time HH:MM (omit = startTime + 1hr)" },
          endDate: { type: "string", description: "End date YYYY-MM-DD for multi-day all-day events" },
          calendar: { type: "string", description: "khal calendar name (omit = default)" },
          location: { type: "string", description: "Event location" },
          description: { type: "string", description: "Event description" },
        },
        required: ["summary", "date"],
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        try {
          const summary = args.summary as string;
          const date = args.date as string;
          const startTime = args.startTime as string | undefined;
          const endTime = args.endTime as string | undefined;
          const endDate = args.endDate as string | undefined;
          const calendar = args.calendar as string | undefined;
          const location = args.location as string | undefined;
          const description = args.description as string | undefined;

          // Validate date format
          if (!DATE_RE.test(date)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid date format: ${date}. Use YYYY-MM-DD.`,
              suggestion: "Provide date in YYYY-MM-DD format (e.g., 2026-04-08)",
            });
          }

          if (endDate && !DATE_RE.test(endDate)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid endDate format: ${endDate}. Use YYYY-MM-DD.`,
              suggestion: "Provide endDate in YYYY-MM-DD format",
            });
          }

          if (startTime && !TIME_RE.test(startTime)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid startTime format: ${startTime}. Use HH:MM.`,
              suggestion: "Provide time in HH:MM format (e.g., 14:00)",
            });
          }

          if (endTime && !TIME_RE.test(endTime)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid endTime format: ${endTime}. Use HH:MM.`,
              suggestion: "Provide time in HH:MM format",
            });
          }

          // Build khal args
          const khalArgs: string[] = ["new"];

          // Add calendar flag if specified
          if (calendar) {
            khalArgs.push("-a", calendar);
          }

          // Add date/time arguments based on event type
          if (startTime) {
            // Timed event: date startTime endTime summary
            const end = endTime || (() => {
              // Default to startTime + 1 hour
              const [h, m] = startTime.split(":").map(Number);
              const endH = (h + 1) % 24;
              return `${String(endH).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
            })();
            khalArgs.push(date, startTime, end, summary);
          } else if (endDate) {
            // Multi-day all-day: date endDate summary
            khalArgs.push(date, endDate, summary);
          } else {
            // Single all-day: date summary
            khalArgs.push(date, summary);
          }

          // Add location if specified
          if (location) {
            khalArgs.push("--location", location);
          }

          // Add description if specified (khal uses :: separator in command line)
          // For description, we need to append ":: description" to the args
          if (description) {
            khalArgs.push("::", description);
          }

          const bin = await khalBin();
          log.debug("khal new", { args: khalArgs });
          const { exitCode, stdout, stderr } = await runBin(bin, khalArgs, { timeout: 10000 });

          if (exitCode !== 0) {
            return mcpError({
              type: "COMMAND_FAILED",
              message: "Failed to create calendar event",
              error: stderr.trim() || stdout.trim() || "khal returned non-zero",
              suggestion: "Check that the date/time format is correct and khal is properly configured",
              context: { date, startTime, endTime, summary },
            });
          }

          // Trigger sync to push to iCloud (fire-and-forget)
          await triggerSync();

          return {
            status: "ok",
            message: `Created event: "${summary}" on ${date}${startTime ? ` at ${startTime}` : " (all-day)"}`,
            data: {
              summary,
              date,
              startTime: startTime || null,
              endTime: endTime || null,
              endDate: endDate || null,
              location: location || null,
              description: description || null,
              calendar: calendar || "default",
              syncTriggered: true,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to create calendar event", err,
            "Check that khal is installed and calendar storage is accessible");
        }
      },
    },

    /* ── Delete event ───────────────────────────────────────────── */
    {
      name: "hwc_calendar_delete",
      description:
        "Delete an iCloud calendar event by searching for it. Two-step safety: call with confirm=false (default) " +
        "to preview matches, then confirm=true to delete. Searches vdirsyncer .ics files by summary text. " +
        "SIDE EFFECT: deletes a real calendar event and syncs deletion to iCloud.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search text to find the event (required)" },
          date: { type: "string", description: "YYYY-MM-DD to narrow search to specific date" },
          confirm: { type: "boolean", description: "If true, actually delete; if false (default), show matches" },
        },
        required: ["query"],
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        try {
          const query = args.query as string;
          const date = args.date as string | undefined;
          const confirm = (args.confirm as boolean) ?? false;

          if (date && !DATE_RE.test(date)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid date format: ${date}. Use YYYY-MM-DD.`,
              suggestion: "Provide date in YYYY-MM-DD format to filter results",
            });
          }

          // Search for matching events
          const matches = await searchIcsFiles(query, date);

          if (matches.length === 0) {
            return {
              status: "ok",
              message: `No events found matching "${query}"${date ? ` on ${date}` : ""}`,
              data: { matches: [], matchCount: 0 },
            };
          }

          // Dry-run: return matches for review
          if (!confirm) {
            return {
              status: "ok",
              message: `Found ${matches.length} event(s) matching "${query}". Set confirm=true to delete.`,
              data: {
                matches: matches.map((m) => ({
                  summary: m.summary,
                  dtstart: m.dtstart,
                  location: m.location,
                  uid: m.uid,
                })),
                matchCount: matches.length,
                action: "dry-run",
              },
            };
          }

          // Confirm mode: require exactly 1 match
          if (matches.length > 1) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Multiple events (${matches.length}) match "${query}". Narrow the search or specify a date.`,
              suggestion: "Add a date filter or use a more specific query to match exactly one event",
              context: {
                matches: matches.map((m) => ({ summary: m.summary, dtstart: m.dtstart })),
              },
            });
          }

          // Delete the single matching event
          const event = matches[0];
          await unlink(event.path);
          log.debug("Deleted .ics file", { path: event.path, summary: event.summary });

          // Trigger sync to push deletion to iCloud
          await triggerSync();

          return {
            status: "ok",
            message: `Deleted event: "${event.summary}"`,
            data: {
              deleted: {
                summary: event.summary,
                dtstart: event.dtstart,
                uid: event.uid,
              },
              syncTriggered: true,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to delete calendar event", err,
            "Check that vdirsyncer calendar storage is accessible");
        }
      },
    },

    /* ── Edit event ─────────────────────────────────────────────── */
    {
      name: "hwc_calendar_edit",
      description:
        "Modify an existing iCloud calendar event. Finds the event by query, then updates specified fields. " +
        "Implemented as delete + recreate. Two-step safety: call with confirm=false (default) to preview " +
        "changes, then confirm=true to apply. SIDE EFFECT: modifies a real calendar event and syncs to iCloud.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search text to find the event to edit (required)" },
          date: { type: "string", description: "YYYY-MM-DD to narrow search to specific date" },
          newSummary: { type: "string", description: "New event title" },
          newDate: { type: "string", description: "New date YYYY-MM-DD" },
          newStartTime: { type: "string", description: "New start time HH:MM" },
          newEndTime: { type: "string", description: "New end time HH:MM" },
          newLocation: { type: "string", description: "New location" },
          newDescription: { type: "string", description: "New description" },
          confirm: { type: "boolean", description: "If true, apply changes; if false (default), preview" },
        },
        required: ["query"],
      },
      handler: async (args: Record<string, unknown>): Promise<ToolResult> => {
        try {
          const query = args.query as string;
          const date = args.date as string | undefined;
          const newSummary = args.newSummary as string | undefined;
          const newDate = args.newDate as string | undefined;
          const newStartTime = args.newStartTime as string | undefined;
          const newEndTime = args.newEndTime as string | undefined;
          const newLocation = args.newLocation as string | undefined;
          const newDescription = args.newDescription as string | undefined;
          const confirm = (args.confirm as boolean) ?? false;

          // Validate date formats
          if (date && !DATE_RE.test(date)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid date format: ${date}. Use YYYY-MM-DD.`,
            });
          }
          if (newDate && !DATE_RE.test(newDate)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid newDate format: ${newDate}. Use YYYY-MM-DD.`,
            });
          }
          if (newStartTime && !TIME_RE.test(newStartTime)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid newStartTime format: ${newStartTime}. Use HH:MM.`,
            });
          }
          if (newEndTime && !TIME_RE.test(newEndTime)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid newEndTime format: ${newEndTime}. Use HH:MM.`,
            });
          }

          // Search for matching events
          const matches = await searchIcsFiles(query, date);

          if (matches.length === 0) {
            return {
              status: "ok",
              message: `No events found matching "${query}"${date ? ` on ${date}` : ""}`,
              data: { matches: [], matchCount: 0 },
            };
          }

          if (matches.length > 1) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Multiple events (${matches.length}) match "${query}". Narrow the search.`,
              suggestion: "Add a date filter or use a more specific query",
              context: {
                matches: matches.map((m) => ({ summary: m.summary, dtstart: m.dtstart })),
              },
            });
          }

          const event = matches[0];

          // Parse existing values from the event
          const existingDate = event.dtstart
            ? event.dtstart.substring(0, 8).replace(/(\d{4})(\d{2})(\d{2})/, "$1-$2-$3")
            : null;
          const existingStartTime = event.dtstart?.includes("T")
            ? event.dtstart.substring(9, 11) + ":" + event.dtstart.substring(11, 13)
            : null;
          const existingEndTime = event.dtend?.includes("T")
            ? event.dtend.substring(9, 11) + ":" + event.dtend.substring(11, 13)
            : null;

          // Merge new values over existing
          const finalSummary = newSummary ?? event.summary;
          const finalDate = newDate ?? existingDate;
          const finalStartTime = newStartTime ?? existingStartTime;
          const finalEndTime = newEndTime ?? existingEndTime;
          const finalLocation = newLocation ?? event.location;
          const finalDescription = newDescription ?? event.description;

          if (!finalDate) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: "Could not determine event date. Provide newDate.",
            });
          }

          const changes = {
            summary: { from: event.summary, to: finalSummary },
            date: { from: existingDate, to: finalDate },
            startTime: { from: existingStartTime, to: finalStartTime },
            endTime: { from: existingEndTime, to: finalEndTime },
            location: { from: event.location, to: finalLocation },
            description: { from: event.description, to: finalDescription },
          };

          // Dry-run: preview changes
          if (!confirm) {
            return {
              status: "ok",
              message: `Preview changes for "${event.summary}". Set confirm=true to apply.`,
              data: {
                original: {
                  summary: event.summary,
                  dtstart: event.dtstart,
                  location: event.location,
                },
                changes,
                action: "dry-run",
              },
            };
          }

          // Apply changes: delete old, create new
          await unlink(event.path);
          log.debug("Deleted old .ics for edit", { path: event.path });

          // Create new event via khal
          const khalArgs: string[] = ["new"];

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

          if (finalLocation) {
            khalArgs.push("--location", finalLocation);
          }

          if (finalDescription) {
            khalArgs.push("::", finalDescription);
          }

          const bin = await khalBin();
          const { exitCode, stderr } = await runBin(bin, khalArgs, { timeout: 10000 });

          if (exitCode !== 0) {
            return mcpError({
              type: "COMMAND_FAILED",
              message: "Deleted old event but failed to create updated event",
              error: stderr.trim(),
              suggestion: "Use hwc_calendar_create to manually recreate the event",
              context: { original: event.summary, changes },
            });
          }

          // Trigger sync
          await triggerSync();

          return {
            status: "ok",
            message: `Updated event: "${event.summary}" → "${finalSummary}"`,
            data: {
              changes,
              syncTriggered: true,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to edit calendar event", err,
            "Check that vdirsyncer calendar storage is accessible");
        }
      },
    },

  ];
}
