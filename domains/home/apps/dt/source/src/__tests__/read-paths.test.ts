import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('session reads project caller fields and preserve summary results', async () => {
  const root = mkdtempSync(join(tmpdir(), 'dt-read-paths-'));
  const oldData = process.env.XDG_DATA_HOME;
  const oldConfig = process.env.XDG_CONFIG_HOME;
  process.env.XDG_DATA_HOME = root;
  process.env.XDG_CONFIG_HOME = join(root, 'config');
  const { getDb } = await import('../db/connection.js');
  const { getActiveSession, getSessionsForInvoice, getCategorySummary, getDaySummaries } = await import('../db/queries.js');
  const db = getDb();
  try {
    db.exec('ALTER TABLE sessions ADD COLUMN unused_blob BLOB');
    db.prepare('INSERT INTO sessions(start_at, category, notes, unused_blob) VALUES (?, ?, ?, ?)')
      .run('2026-10-01T09:00:00Z', 'dev', 'large note'.repeat(10000), Buffer.alloc(1000000));
    assert.deepEqual(getActiveSession(['start_at']), { start_at: '2026-10-01T09:00:00Z' });
    assert.deepEqual(Object.keys(getActiveSession(['id', 'start_at', 'category', 'pomodoros_notified'])!),
      ['id', 'start_at', 'category', 'pomodoros_notified']);
    assert.deepEqual(Object.keys(getActiveSession()!), ['id', 'start_at', 'end_at', 'category', 'notes', 'pomodoros_notified']);
    db.prepare('UPDATE sessions SET end_at = ?, notes = ?').run('2026-10-01T10:00:00Z', 'finished');
    assert.equal(getActiveSession(['id']), null);
    const from = '2026-10-01T00:00:00Z', to = '2026-10-01T23:59:59Z';
    assert.deepEqual(Object.keys(getSessionsForInvoice(from, to, false)[0]), ['start_at', 'end_at', 'category']);
    assert.deepEqual(Object.keys(getSessionsForInvoice(from, to)[0]), ['start_at', 'end_at', 'category', 'notes']);
    assert.deepEqual(getCategorySummary(from, to), [{ category: 'dev', total_minutes: 60 }]);
    assert.deepEqual(getDaySummaries(from, to), [{ date: '2026-10-01', category: 'dev', total_minutes: 60, notes: ['finished'] }]);
  } finally {
    db.close();
    if (oldData === undefined) delete process.env.XDG_DATA_HOME; else process.env.XDG_DATA_HOME = oldData;
    if (oldConfig === undefined) delete process.env.XDG_CONFIG_HOME; else process.env.XDG_CONFIG_HOME = oldConfig;
    rmSync(root, { recursive: true, force: true });
  }
});
