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

import { execFile } from "node:child_process";
import { catchError } from "../errors.js";
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

  ];
}
