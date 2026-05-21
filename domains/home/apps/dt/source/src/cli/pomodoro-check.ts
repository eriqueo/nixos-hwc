import { execSync } from 'node:child_process';
import { getActiveSession, setPomodorosNotified } from '../db/queries.js';
import { loadConfig } from '../config/index.js';
import { elapsedMinutes, formatDuration } from '../lib/time.js';

// Designed for a systemd user timer that fires every minute while clocked in.
// On each tick: if elapsed minutes have crossed another pomodoro boundary
// since the last notification, fire notify-send and bump the counter.
export function cmdPomodoroCheck(): void {
  const config = loadConfig();
  const interval = Math.max(1, Math.round(config.pomodoro_minutes ?? 25));

  const active = getActiveSession();
  if (!active) return;

  const mins = elapsedMinutes(active.start_at);
  const expected = Math.floor(mins / interval);
  const seen = active.pomodoros_notified ?? 0;

  if (expected <= seen) return;

  setPomodorosNotified(active.id, expected);

  const minutesIn = expected * interval;
  const cat = active.category ? ` [${active.category}]` : '';
  const title = `dt — ${minutesIn}-min mark`;
  const body = `${formatDuration(mins)} on the clock${cat}. Time for a break?`;

  try {
    execSync(
      `notify-send -u low -a dt "${title.replace(/"/g, '\\"')}" "${body.replace(/"/g, '\\"')}"`,
      { stdio: 'ignore' }
    );
  } catch {
    // notify-send not installed or DBus unavailable — silent
  }
}
