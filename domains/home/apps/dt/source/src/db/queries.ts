import { getDb } from './connection.js';
import type { Session, Category, CategorySummary, DaySummary } from '../lib/types.js';
import { nowISO, splitAcrossDays } from '../lib/time.js';
import { writeEvent, removeEvent } from '../lib/calendar.js';

// ── Sessions ──────────────────────────────────────────────

export function getActiveSession(): Session | null {
  const db = getDb();
  return db.prepare('SELECT * FROM sessions WHERE end_at IS NULL LIMIT 1').get() as Session | null;
}

export function startSession(category?: string | null): Session {
  const db = getDb();
  const active = getActiveSession();
  if (active) {
    throw new Error(`Already clocked in since ${active.start_at}`);
  }
  const now = nowISO();
  const result = db.prepare(
    'INSERT INTO sessions (start_at, category) VALUES (?, ?) RETURNING *'
  ).get(now, category ?? null) as Session;
  return result;
}

export function endSession(notes?: string | null, category?: string | null): Session {
  const db = getDb();
  const active = getActiveSession();
  if (!active) {
    throw new Error('Not clocked in');
  }
  const now = nowISO();
  const updates: string[] = ['end_at = ?'];
  const params: any[] = [now];

  if (notes !== undefined && notes !== null) {
    updates.push('notes = ?');
    params.push(notes);
  }
  if (category !== undefined && category !== null) {
    updates.push('category = ?');
    params.push(category);
  }

  params.push(active.id);
  const result = db.prepare(
    `UPDATE sessions SET ${updates.join(', ')} WHERE id = ? RETURNING *`
  ).get(...params) as Session;
  writeEvent(result);
  return result;
}

export function getSessionsByRange(from: string, to: string): Session[] {
  const db = getDb();
  return db.prepare(`
    SELECT * FROM sessions
    WHERE start_at >= ? AND (start_at <= ? OR end_at IS NULL)
    ORDER BY start_at ASC
  `).all(from, to) as Session[];
}

export function getSessionsForInvoice(from: string, to: string): Session[] {
  const db = getDb();
  return db.prepare(`
    SELECT * FROM sessions
    WHERE start_at >= ? AND start_at <= ? AND end_at IS NOT NULL
    ORDER BY start_at ASC
  `).all(from, to) as Session[];
}

export function getCategorySummary(from: string, to: string): CategorySummary[] {
  const db = getDb();
  const sessions = getSessionsForInvoice(from, to);
  const totals = new Map<string, number>();

  for (const s of sessions) {
    if (!s.end_at) continue;
    const cat = s.category || 'other';
    const days = splitAcrossDays(s.start_at, s.end_at);
    // Filter to only days within the range
    const fromDate = from.split('T')[0];
    const toDate = to.split('T')[0];
    for (const d of days) {
      if (d.date >= fromDate && d.date <= toDate) {
        totals.set(cat, (totals.get(cat) || 0) + d.minutes);
      }
    }
  }

  return Array.from(totals.entries())
    .map(([category, total_minutes]) => ({ category, total_minutes }))
    .sort((a, b) => b.total_minutes - a.total_minutes);
}

export function getDaySummaries(from: string, to: string): DaySummary[] {
  const sessions = getSessionsForInvoice(from, to);
  const map = new Map<string, DaySummary>();
  const fromDate = from.split('T')[0];
  const toDate = to.split('T')[0];

  for (const s of sessions) {
    if (!s.end_at) continue;
    const days = splitAcrossDays(s.start_at, s.end_at);
    for (const d of days) {
      if (d.date < fromDate || d.date > toDate) continue;
      const cat = s.category || 'other';
      const key = `${d.date}|${cat}`;
      const existing = map.get(key);
      if (existing) {
        existing.total_minutes += d.minutes;
        if (s.notes) existing.notes.push(s.notes);
      } else {
        map.set(key, {
          date: d.date,
          category: cat,
          total_minutes: d.minutes,
          notes: s.notes ? [s.notes] : [],
        });
      }
    }
  }

  return Array.from(map.values()).sort((a, b) =>
    a.date === b.date ? a.category.localeCompare(b.category) : a.date.localeCompare(b.date)
  );
}

export function updateSession(id: number, fields: Partial<Pick<Session, 'start_at' | 'end_at' | 'category' | 'notes'>>): Session {
  const db = getDb();
  const sets: string[] = [];
  const params: any[] = [];

  if (fields.start_at !== undefined) { sets.push('start_at = ?'); params.push(fields.start_at); }
  if (fields.end_at !== undefined) { sets.push('end_at = ?'); params.push(fields.end_at); }
  if (fields.category !== undefined) { sets.push('category = ?'); params.push(fields.category); }
  if (fields.notes !== undefined) { sets.push('notes = ?'); params.push(fields.notes); }

  if (sets.length === 0) throw new Error('No fields to update');
  params.push(id);

  const result = db.prepare(
    `UPDATE sessions SET ${sets.join(', ')} WHERE id = ? RETURNING *`
  ).get(...params) as Session;

  if (!result) throw new Error(`Session ${id} not found`);
  writeEvent(result);
  return result;
}

export function deleteSession(id: number): void {
  const db = getDb();
  const result = db.prepare('DELETE FROM sessions WHERE id = ?').run(id);
  if (result.changes === 0) throw new Error(`Session ${id} not found`);
  removeEvent(id);
}

export function setPomodorosNotified(id: number, count: number): void {
  const db = getDb();
  db.prepare('UPDATE sessions SET pomodoros_notified = ? WHERE id = ?').run(count, id);
}

// ── Categories ────────────────────────────────────────────

export function getCategories(): Category[] {
  const db = getDb();
  return db.prepare('SELECT * FROM categories ORDER BY slug').all() as Category[];
}

export function addCategory(slug: string, label: string, color: string = '#928374'): Category {
  const db = getDb();
  return db.prepare(
    'INSERT INTO categories (slug, label, color) VALUES (?, ?, ?) RETURNING *'
  ).get(slug, label, color) as Category;
}
