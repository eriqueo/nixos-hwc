import { getDb } from '../db/connection.js';
import { updateSession } from '../db/queries.js';
import type { Session } from '../lib/types.js';

function resolveTimeArg(input: string, referenceDate: string): string {
  // If it looks like HH:MM, resolve to ISO on the reference date
  if (/^\d{1,2}:\d{2}$/.test(input)) {
    const [h, m] = input.split(':').map(Number);
    const d = new Date(referenceDate);
    d.setHours(h, m, 0, 0);
    return d.toISOString();
  }
  // Otherwise treat as ISO
  return new Date(input).toISOString();
}

export function cmdAmend(
  target: string,
  opts: { start?: string; end?: string; category?: string; notes?: string }
): void {
  const db = getDb();
  let session: Session;

  if (target === 'last') {
    const row = db.prepare('SELECT * FROM sessions ORDER BY start_at DESC LIMIT 1').get() as Session | undefined;
    if (!row) {
      console.error('No sessions found');
      process.exit(1);
    }
    session = row;
  } else {
    const id = parseInt(target);
    if (isNaN(id)) {
      console.error('Target must be "last" or a session ID');
      process.exit(1);
    }
    const row = db.prepare('SELECT * FROM sessions WHERE id = ?').get(id) as Session | undefined;
    if (!row) {
      console.error(`Session ${id} not found`);
      process.exit(1);
    }
    session = row;
  }

  const fields: Partial<Pick<Session, 'start_at' | 'end_at' | 'category' | 'notes'>> = {};
  if (opts.start) fields.start_at = resolveTimeArg(opts.start, session.start_at);
  if (opts.end) fields.end_at = resolveTimeArg(opts.end, session.start_at);
  if (opts.category) fields.category = opts.category;
  if (opts.notes) fields.notes = opts.notes;

  if (Object.keys(fields).length === 0) {
    console.error('No changes specified. Use --start, --end, -c, or -n.');
    process.exit(1);
  }

  const updated = updateSession(session.id, fields);
  console.log(`Session ${updated.id} updated:`);
  console.log(`  start: ${updated.start_at}`);
  console.log(`  end:   ${updated.end_at || '(active)'}`);
  console.log(`  cat:   ${updated.category || '(none)'}`);
  console.log(`  notes: ${updated.notes || '(none)'}`);
}
