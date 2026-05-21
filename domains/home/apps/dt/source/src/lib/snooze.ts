import fs from 'node:fs';
import path from 'node:path';

function snoozePath(): string {
  const state = process.env.XDG_STATE_HOME || path.join(process.env.HOME || '~', '.local/state');
  const dir = path.join(state, 'dt');
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, 'stale-snooze-until');
}

export function snoozeUntil(): number | null {
  try {
    const raw = fs.readFileSync(snoozePath(), 'utf-8').trim();
    const n = parseInt(raw, 10);
    return Number.isFinite(n) ? n : null;
  } catch {
    return null;
  }
}

export function isSnoozeActive(): boolean {
  const until = snoozeUntil();
  return until !== null && Date.now() / 1000 < until;
}

export function setSnoozeMinutes(minutes: number): void {
  const until = Math.floor(Date.now() / 1000) + minutes * 60;
  fs.writeFileSync(snoozePath(), String(until));
}
