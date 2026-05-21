import fs from 'node:fs';
import { execSync } from 'node:child_process';
import { configPath, loadConfig } from '../config/index.js';
import { calendarDir } from '../lib/calendar.js';
import { getDb, dbPath } from '../db/connection.js';
import { getActiveSession } from '../db/queries.js';
import { elapsedMinutes, formatDuration } from '../lib/time.js';

type Result = { ok: boolean; label: string; detail?: string };

function tryRun(label: string, fn: () => string | void): Result {
  try {
    const detail = fn();
    return { ok: true, label, detail: detail || undefined };
  } catch (e) {
    return { ok: false, label, detail: (e as Error).message };
  }
}

function checkTimer(name: string): Result {
  return tryRun(`systemd user timer: ${name}`, () => {
    const out = execSync(`systemctl --user is-active ${name}`, { encoding: 'utf-8' }).trim();
    if (out !== 'active') throw new Error(`is-active=${out}`);
    return out;
  });
}

export function cmdDoctor(): void {
  const results: Result[] = [];

  results.push(tryRun('config file readable', () => {
    const p = configPath();
    if (!fs.existsSync(p)) throw new Error(`missing ${p}`);
    loadConfig();
    return p;
  }));

  results.push(tryRun('database opens (better-sqlite3 ABI ok)', () => {
    const db = getDb();
    db.prepare('SELECT 1').get();
    return dbPath();
  }));

  results.push(tryRun('database writable', () => {
    const p = dbPath();
    fs.accessSync(p, fs.constants.W_OK);
    return p;
  }));

  results.push(tryRun('active session', () => {
    const s = getActiveSession();
    if (!s) return 'none (idle)';
    const dur = formatDuration(elapsedMinutes(s.start_at));
    return `#${s.id} [${s.category || 'other'}] ${dur}`;
  }));

  results.push(tryRun('calendar dir writable', () => {
    const dir = calendarDir();
    fs.mkdirSync(dir, { recursive: true });
    fs.accessSync(dir, fs.constants.W_OK);
    return dir;
  }));

  results.push(tryRun('notify-send available', () => {
    execSync('command -v notify-send', { stdio: 'ignore' });
    return 'ok';
  }));

  results.push(checkTimer('dt-stale-check.timer'));
  results.push(checkTimer('dt-pomodoro.timer'));

  // Pretty-print
  let failed = 0;
  for (const r of results) {
    const mark = r.ok ? '[32m✓[0m' : '[31m✗[0m';
    const detail = r.detail ? ` — ${r.detail}` : '';
    console.log(`${mark} ${r.label}${detail}`);
    if (!r.ok) failed++;
  }

  console.log();
  if (failed === 0) {
    console.log('[32mAll checks passed.[0m');
  } else {
    console.log(`[31m${failed} check(s) failed.[0m`);
    process.exit(1);
  }
}
