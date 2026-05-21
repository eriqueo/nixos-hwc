import type Database from 'better-sqlite3';

const DEFAULT_CATEGORIES = [
  { slug: 'support', label: 'Support', color: '#a9b665' },
  { slug: 'infra', label: 'Infrastructure', color: '#7daea3' },
  { slug: 'dev', label: 'Development', color: '#d8a657' },
  { slug: 'meetings', label: 'Meetings', color: '#d3869b' },
  { slug: 'strategy', label: 'Strategy', color: '#e78a4e' },
  { slug: 'lead_scout', label: 'Lead Scout', color: '#89b482' },
  { slug: 'other', label: 'Other', color: '#928374' },
];

export function initSchema(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      slug TEXT UNIQUE NOT NULL,
      label TEXT NOT NULL,
      color TEXT NOT NULL DEFAULT '#928374'
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      start_at TEXT NOT NULL,
      end_at TEXT,
      category TEXT REFERENCES categories(slug),
      notes TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start_at);
    CREATE INDEX IF NOT EXISTS idx_sessions_end ON sessions(end_at);
  `);

  // Migrations (additive; safe to run on every startup)
  const cols = db.prepare("PRAGMA table_info(sessions)").all() as Array<{ name: string }>;
  const colNames = new Set(cols.map((c) => c.name));
  if (!colNames.has('pomodoros_notified')) {
    db.exec("ALTER TABLE sessions ADD COLUMN pomodoros_notified INTEGER NOT NULL DEFAULT 0");
  }

  // Seed default categories if empty
  const count = db.prepare('SELECT COUNT(*) as c FROM categories').get() as { c: number };
  if (count.c === 0) {
    const insert = db.prepare('INSERT INTO categories (slug, label, color) VALUES (?, ?, ?)');
    const tx = db.transaction(() => {
      for (const cat of DEFAULT_CATEGORIES) {
        insert.run(cat.slug, cat.label, cat.color);
      }
    });
    tx();
  }
}
