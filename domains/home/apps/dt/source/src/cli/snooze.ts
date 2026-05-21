import { setSnoozeMinutes } from '../lib/snooze.js';

export function cmdSnooze(opts: { minutes?: string }): void {
  const m = parseInt(opts.minutes || '15', 10);
  if (!Number.isFinite(m) || m <= 0) {
    console.error('snooze: --minutes must be a positive integer');
    process.exit(2);
  }
  setSnoozeMinutes(m);
  console.log(`Stale notifications snoozed for ${m} minute(s).`);
}
