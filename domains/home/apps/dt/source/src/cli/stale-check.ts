import { spawn } from 'node:child_process';
import { getActiveSession } from '../db/queries.js';
import { loadConfig } from '../config/index.js';
import { elapsedMinutes, formatDuration } from '../lib/time.js';
import { isSnoozeActive } from '../lib/snooze.js';

export function cmdStaleCheck(): void {
  const config = loadConfig();
  const active = getActiveSession();
  if (!active) return;

  const mins = elapsedMinutes(active.start_at);
  if (mins / 60 < config.max_session_hours) return;

  if (isSnoozeActive()) return;

  // Hand off to the notifier wrapper (installed by the Nix module). It calls
  // `notify-send --action` and dispatches the chosen action (clock-out /
  // snooze). Detach so the systemd service exits while the prompt is open.
  const dur = formatDuration(mins);
  const body = `Session running for ${dur} — forgot to clock out?`;

  try {
    const child = spawn('dt-stale-notifier', [body], {
      detached: true,
      stdio: 'ignore',
    });
    child.unref();
  } catch {
    // notifier missing — silent (matches old behavior)
  }
}
