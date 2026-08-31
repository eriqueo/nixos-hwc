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
  002-calculator-leads.sql   # hwc.calculator_leads table for work_calculator_lead
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
- 2026-07-07: Deleted `003-notification-events.sql` in the Slack/gotify
  eradication — `hwc-notify` is the sole notification path, so the n8n-side
  event table had no writer left (`fbd92674`).
- 2026-03-31: Added `003-notification-events.sql` (`17b9283b`); removed again
  2026-07-07.
- 2026-03-26: Added `002-calculator-leads.sql` — the `hwc.calculator_leads`
  table backing the `work_calculator_lead` workflow (`330f739d`). `Structure`
  updated to list it.
- 2026-03-26: Added 002-full-hwc-schema.sql — full production schema with JT reference tables, cost catalog, project state, estimates, leads, daily logs, workflow log, and views
