import { getSessionsByRange } from '../db/queries.js';
import { parseDate, dateRange, elapsedMinutes, formatDuration } from '../lib/time.js';

export function cmdLog(period: string = 'today'): void {
  const date = parseDate(period);
  const range = dateRange(date, date);
  const sessions = getSessionsByRange(range.from, range.to);

  if (sessions.length === 0) {
    console.log(`No sessions on ${date}`);
    return;
  }

  console.log(`${date}:`);
  let totalMins = 0;
  for (const s of sessions) {
    const start = new Date(s.start_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    const end = s.end_at
      ? new Date(s.end_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      : 'now';
    const mins = elapsedMinutes(s.start_at, s.end_at);
    totalMins += mins;
    const cat = (s.category || 'other').padEnd(14);
    const notes = s.notes ? `  ${s.notes}` : '';
    console.log(`  ${start} - ${end}  ${cat} ${formatDuration(mins)}${notes}`);
  }
  console.log(`  ${'─'.repeat(40)}`);
  console.log(`  ${'TOTAL'.padEnd(28)} ${formatDuration(totalMins)}`);
}
