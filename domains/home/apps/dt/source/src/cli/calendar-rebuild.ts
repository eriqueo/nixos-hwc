import fs from 'node:fs';
import path from 'node:path';
import { getDb } from '../db/connection.js';
import { writeEvent, calendarDir } from '../lib/calendar.js';
import type { Session } from '../lib/types.js';

export function cmdCalendarRebuild(): void {
  const dir = calendarDir();

  // Wipe existing dt-*.ics so deletions/amends are reflected.
  try {
    fs.mkdirSync(dir, { recursive: true });
    for (const f of fs.readdirSync(dir)) {
      if (f.startsWith('dt-') && f.endsWith('.ics')) {
        try { fs.unlinkSync(path.join(dir, f)); } catch { /* ignore */ }
      }
    }
  } catch (e) {
    console.error(`Cannot write to ${dir}: ${(e as Error).message}`);
    process.exit(1);
  }

  const db = getDb();
  const sessions = db
    .prepare('SELECT * FROM sessions WHERE end_at IS NOT NULL ORDER BY start_at ASC')
    .all() as Session[];

  let count = 0;
  for (const s of sessions) {
    writeEvent(s);
    count++;
  }

  console.log(`Wrote ${count} session(s) to ${dir}`);
}
