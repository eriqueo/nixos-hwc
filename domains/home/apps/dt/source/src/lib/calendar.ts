import fs from 'node:fs';
import path from 'node:path';
import { loadConfig } from '../config/index.js';
import type { Session } from './types.js';

function defaultDir(): string {
  const xdg = process.env.XDG_DATA_HOME || path.join(process.env.HOME || '~', '.local/share');
  return path.join(xdg, 'dt', 'calendar');
}

export function calendarDir(): string {
  const cfg = loadConfig();
  return cfg.calendar_dir ?? defaultDir();
}

function escapeIcs(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/\n/g, '\\n')
    .replace(/,/g, '\\,')
    .replace(/;/g, '\\;');
}

function isoToIcsUtc(iso: string): string {
  // ISO 8601 → YYYYMMDDTHHMMSSZ (UTC). Sessions are stored as local ISO with
  // offset; Date() normalizes to UTC for us.
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return (
    `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`
  );
}

function eventPath(id: number): string {
  return path.join(calendarDir(), `dt-${id}.ics`);
}

function sessionToIcs(s: Session): string {
  if (!s.end_at) throw new Error(`session ${s.id} has no end_at`);
  const dtstart = isoToIcsUtc(s.start_at);
  const dtend = isoToIcsUtc(s.end_at);
  const dtstamp = isoToIcsUtc(new Date().toISOString());
  const summary = `dt: ${s.category || 'other'}`;
  const description = s.notes ? escapeIcs(s.notes) : '';
  const uid = `dt-session-${s.id}@local`;

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//hwc//dt//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `DTSTAMP:${dtstamp}`,
    `DTSTART:${dtstart}`,
    `DTEND:${dtend}`,
    `SUMMARY:${escapeIcs(summary)}`,
    `DESCRIPTION:${description}`,
    `CATEGORIES:${escapeIcs(s.category || 'other')}`,
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

export function writeEvent(s: Session): void {
  if (!s.end_at) return; // open sessions don't get written
  const dir = calendarDir();
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(eventPath(s.id), sessionToIcs(s), 'utf-8');
  } catch {
    // calendar writes are best-effort; never block tracking
  }
}

export function removeEvent(id: number): void {
  try {
    fs.unlinkSync(eventPath(id));
  } catch {
    // file missing is fine
  }
}
