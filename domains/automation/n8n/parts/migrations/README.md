# migrations

## Purpose
SQL migration files for the `hwc` PostgreSQL database. Applied in order against the `hwc` database on the homeserver.

## Boundaries
- All tables live in the `hwc` schema
- Migrations are numbered sequentially: `NNN-description.sql`
- Each migration is idempotent (`CREATE TABLE IF NOT EXISTS`, `ON CONFLICT DO NOTHING`)

## Structure
```
migrations/
  001-estimates-table.sql    # Initial estimates table (early prototype)
  002-calculator-leads.sql   # Calculator lead capture table
  002-full-hwc-schema.sql    # Full production schema: all 11 tables, 5 views, seed data
```

## Applying Migrations
```bash
sudo -u postgres psql -d hwc -f 002-full-hwc-schema.sql
```

If the database doesn't exist yet:
```bash
sudo -u postgres createdb hwc
sudo -u postgres psql -d hwc -f 002-full-hwc-schema.sql
```

## Changelog
- 2026-07-07: Deleted `003-notification-events.sql` — the Slack/gotify
  eradication removed the n8n-side notification event table; `hwc-notify` in
  `domains/notifications/` owns delivery and its own state.
- 2026-03-31: `003-notification-events.sql` added (17b9283b) — since deleted, see
  above. `002-calculator-leads.sql` (added 2026-03-26 with the
  work_calculator_lead workflow) was never listed in Structure; added now.
- 2026-03-26: Added 002-full-hwc-schema.sql — full production schema with JT reference tables, cost catalog, project state, estimates, leads, daily logs, workflow log, and views
