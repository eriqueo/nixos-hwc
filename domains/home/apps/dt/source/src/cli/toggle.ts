import { getActiveSession, startSession, endSession } from '../db/queries.js';
import { loadConfig } from '../config/index.js';
import { elapsedMinutes, formatDuration } from '../lib/time.js';

export function cmdToggle(category?: string): void {
  const config = loadConfig();
  const active = getActiveSession();

  if (active) {
    const session = endSession();
    const mins = elapsedMinutes(session.start_at, session.end_at);
    console.log(`Out: ${formatDuration(mins)}`);
  } else {
    const cat = category || config.default_category || undefined;
    const session = startSession(cat);
    const label = session.category ? ` [${session.category}]` : '';
    console.log(`In${label}`);
  }
}
