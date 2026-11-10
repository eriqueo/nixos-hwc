import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import Database from 'better-sqlite3';
import { initSchema } from '../db/schema.js';

test('packaged CLI produces a complete invoice from stored sessions', () => {
  const root = mkdtempSync(join(tmpdir(), 'dt-export-'));
  try {
    const source = fileURLToPath(new URL('../../', import.meta.url));
    const manifest = JSON.parse(readFileSync(join(source, 'package.json'), 'utf-8'));
    const executable = join(source, manifest.bin.dt);
    assert.match(execFileSync(process.execPath, [executable, '--help'], { encoding: 'utf-8' }), /Generate PDF invoice/);
    const config = join(root, 'config', 'dt', 'config.toml');
    mkdirSync(dirname(config), { recursive: true });
    writeFileSync(config, 'name = "Fixture Person"\nrate = 40\n');
    const dbFile = join(root, 'data', 'dt', 'dt.sqlite');
    mkdirSync(dirname(dbFile), { recursive: true });
    const db = new Database(dbFile);
    initSchema(db);
    db.prepare('INSERT INTO sessions(start_at, end_at, category, notes) VALUES (?, ?, ?, ?)')
      .run('2026-10-01T09:00:00Z', '2026-10-01T11:30:00Z', 'dev', 'Fixture delivery');
    db.close();
    const env = { ...process.env, HOME: root, XDG_DATA_HOME: join(root, 'data'),
      XDG_CONFIG_HOME: join(root, 'config'), TZ: 'UTC' };
    const output = execFileSync(process.execPath,
      [executable, 'export', '--from', '2026-10-01', '--to', '2026-10-01'],
      { env, encoding: 'utf-8', timeout: 10000 });
    const pdf = join(root, 'Documents', 'datax-time', 'invoice-2026-10-01-to-2026-10-01.pdf');
    assert.match(output, /invoice-2026-10-01-to-2026-10-01\.pdf/);
    const bytes = readFileSync(pdf);
    assert.equal(bytes.subarray(0, 5).toString(), '%PDF-');
    assert.match(bytes.subarray(-32).toString(), /%%EOF/);
    const text = execFileSync('pdftotext', [pdf, '-'], { encoding: 'utf-8' });
    for (const expected of ['INVOICE', 'Fixture Person', 'Fixture delivery', 'dev', '2.50', '$100.00']) {
      assert.ok(text.includes(expected), `${expected} missing from invoice: ${text}`);
    }
    for (const [period, heading] of [['week', 'Week'], ['month', 'Month']]) {
      const summary = execFileSync(process.execPath, [executable, period, '--back', '0'],
        { env, encoding: 'utf-8', timeout: 10000 });
      assert.match(summary, new RegExp(`^${heading} \\(current\\):`));
      assert.match(summary, /TOTAL\s+0m/);
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
