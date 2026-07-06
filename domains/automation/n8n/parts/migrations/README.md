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
  001-estimates-table.sql       # Initial estimates table (early prototype)
  002-full-hwc-schema.sql       # Full production schema: all 11 tables, 5 views, seed data
  002-calculator-leads.sql      # hwc.calculator_leads — website bathroom-calculator lead capture
  003-notification-events.sql   # hwc.notification_events — sys:router:notify durable event log
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
- 2026-07-06: Added `003-notification-events.sql` — `hwc.notification_events`, the durable event log for the `sys:router:notify` taxonomy (universe/domain/source/category/severity + Slack/Gotify routing-audit flags + JSONB metadata + reserved self-healing columns), with five supporting indexes.
- 2026-07-06: Added `002-calculator-leads.sql` — creates the `hwc` schema and `hwc.calculator_leads` table (contact, project toggles, estimate range, JT account/job refs, pipeline `status`), archiving leads from the website bathroom cost calculator. Written by the `work_calculator_lead` n8n workflow after JT account creation.
- 2026-03-26: Added 002-full-hwc-schema.sql — full production schema with JT reference tables, cost catalog, project state, estimates, leads, daily logs, workflow log, and views
