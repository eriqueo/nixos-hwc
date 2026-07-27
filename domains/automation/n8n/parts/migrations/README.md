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
  002-calculator-leads.sql   # hwc schema + calculator_leads table (work_calculator_lead workflow)
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
- 2026-07-07: Removed `003-notification-events.sql` (and dropped the live `hwc.notification_events` table, 0 readers) as part of the Slack/gotify → hwc-notify notification unification (fbd92674).
- 2026-03-26: Added `002-calculator-leads.sql` — `hwc` schema + `calculator_leads` table backing the `work_calculator_lead` n8n workflow (330f739d). (`003-notification-events.sql` added 2026-03-31, later removed — see above.)
- 2026-03-26: Added 002-full-hwc-schema.sql — full production schema with JT reference tables, cost catalog, project state, estimates, leads, daily logs, workflow log, and views
