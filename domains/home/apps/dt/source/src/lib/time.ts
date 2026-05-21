export function elapsedMinutes(start: string, end?: string | null): number {
  const s = new Date(start).getTime();
  const e = end ? new Date(end).getTime() : Date.now();
  return Math.max(0, Math.round((e - s) / 60000));
}

export function formatDuration(totalMinutes: number): string {
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  if (h === 0) return `${m}m`;
  if (m === 0) return `${h}h`;
  return `${h}h ${m}m`;
}

export function formatHoursDecimal(totalMinutes: number): string {
  return (totalMinutes / 60).toFixed(2);
}

export function formatCurrency(amount: number): string {
  return `$${amount.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function nowISO(): string {
  return new Date().toISOString();
}

export function todayRange(): { from: string; to: string } {
  const d = new Date();
  const date = d.toISOString().split('T')[0];
  return { from: `${date}T00:00:00.000Z`, to: `${date}T23:59:59.999Z` };
}

export function weekRange(back: number = 0): { from: string; to: string } {
  const now = new Date();
  const day = now.getDay(); // 0=Sun
  const mondayOffset = day === 0 ? -6 : 1 - day;
  const monday = new Date(now);
  monday.setDate(now.getDate() + mondayOffset - back * 7);
  monday.setHours(0, 0, 0, 0);
  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  sunday.setHours(23, 59, 59, 999);
  return { from: monday.toISOString(), to: sunday.toISOString() };
}

export function monthRange(back: number = 0): { from: string; to: string } {
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth() - back;
  const from = new Date(y, m, 1);
  const to = new Date(y, m + 1, 0, 23, 59, 59, 999);
  return { from: from.toISOString(), to: to.toISOString() };
}

export function dateRange(from: string, to: string): { from: string; to: string } {
  return {
    from: `${from}T00:00:00.000Z`,
    to: `${to}T23:59:59.999Z`,
  };
}

/** Split a session across midnight boundaries for per-day reporting */
export function splitAcrossDays(start: string, end: string): { date: string; minutes: number }[] {
  const results: { date: string; minutes: number }[] = [];
  let cursor = new Date(start);
  const endDate = new Date(end);

  while (cursor < endDate) {
    const dayEnd = new Date(cursor);
    dayEnd.setHours(23, 59, 59, 999);
    const segEnd = dayEnd < endDate ? dayEnd : endDate;
    const mins = Math.round((segEnd.getTime() - cursor.getTime()) / 60000);
    if (mins > 0) {
      results.push({ date: cursor.toISOString().split('T')[0], minutes: mins });
    }
    cursor = new Date(dayEnd);
    cursor.setDate(cursor.getDate());
    cursor.setHours(24, 0, 0, 0); // start of next day
  }

  return results;
}

export function parseDate(input: string): string {
  if (input === 'today') return new Date().toISOString().split('T')[0];
  if (input === 'yesterday') {
    const d = new Date();
    d.setDate(d.getDate() - 1);
    return d.toISOString().split('T')[0];
  }
  // Validate YYYY-MM-DD
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input)) {
    throw new Error(`Invalid date: ${input}. Use YYYY-MM-DD, "today", or "yesterday".`);
  }
  return input;
}
