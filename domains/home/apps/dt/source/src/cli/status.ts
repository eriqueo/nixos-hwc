import { getActiveSession } from '../db/queries.js';
import { loadConfig } from '../config/index.js';
import { elapsedMinutes, formatDuration } from '../lib/time.js';
import type { WaybarOutput, SessionState } from '../lib/types.js';

export function cmdStatus(opts: { waybar?: boolean; json?: boolean }): void {
  const config = loadConfig();
  const active = getActiveSession();

  if (!active) {
    if (opts.waybar) {
      const out: WaybarOutput = {
        text: ' DT',
        tooltip: 'DataX: not clocked in (click to open TUI)',
        class: 'idle',
        percentage: 0,
      };
      console.log(JSON.stringify(out));
    } else if (opts.json) {
      console.log(JSON.stringify({ state: 'idle' as SessionState, session: null }));
    } else {
      console.log('Not clocked in');
    }
    return;
  }

  const mins = elapsedMinutes(active.start_at);
  const hours = mins / 60;
  const isStale = hours >= config.max_session_hours;
  const state: SessionState = isStale ? 'stale' : 'active';
  const dur = formatDuration(mins);
  const cat = active.category ? ` [${active.category}]` : '';

  if (opts.waybar) {
    const icon = isStale ? '⚠' : '';
    const out: WaybarOutput = {
      text: `${icon} ${dur}`,
      tooltip: `DataX: ${dur}${cat}\nStarted: ${new Date(active.start_at).toLocaleTimeString()}${isStale ? '\n⚠ STALE SESSION' : ''}`,
      class: state,
      percentage: Math.min(100, Math.round((hours / config.max_session_hours) * 100)),
    };
    console.log(JSON.stringify(out));
  } else if (opts.json) {
    console.log(JSON.stringify({ state, session: active, elapsed_minutes: mins }));
  } else {
    const staleTag = isStale ? ' ⚠ STALE' : '';
    console.log(`Clocked in: ${dur}${cat}${staleTag}`);
  }
}
