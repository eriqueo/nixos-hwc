import Database from 'better-sqlite3';
import path from 'node:path';
import fs from 'node:fs';
import { initSchema } from './schema.js';

let _db: Database.Database | null = null;

export function dbPath(): string {
  const xdg = process.env.XDG_DATA_HOME || path.join(process.env.HOME || '~', '.local', 'share');
  const dir = path.join(xdg, 'dt');
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, 'dt.sqlite');
}

export function getDb(): Database.Database {
  if (_db) return _db;

  _db = new Database(dbPath());
  _db.pragma('journal_mode = WAL');
  _db.pragma('foreign_keys = ON');
  initSchema(_db);

  return _db;
}
