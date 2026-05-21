import { endSession, getActiveSession } from '../db/queries.js';
import { elapsedMinutes, formatDuration } from '../lib/time.js';

export function cmdOut(opts: { notes?: string; category?: string }): void {
  try {
    const active = getActiveSession();
    if (!active) {
      console.error('Not clocked in');
      process.exit(1);
    }
    const session = endSession(opts.notes, opts.category);
    const mins = elapsedMinutes(session.start_at, session.end_at);
    console.log(`Clocked out. Session: ${formatDuration(mins)}`);
  } catch (e: any) {
    console.error(e.message);
    process.exit(1);
  }
}
