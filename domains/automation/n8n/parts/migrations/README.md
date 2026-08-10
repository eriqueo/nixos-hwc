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
  002-calculator-leads.sql   # hwc.calculator_leads — website calculator submissions
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
- 2026-07-07: Deleted `003-notification-events.sql` (fbd92674) — the Slack/gotify
  eradication removed the `hwc.notification_events` log it created; hwc-notify is
  now the sole notification path and owns its own state.
- 2026-03-31: Added `003-notification-events.sql` (17b9283b) — durable event log
  for the then-current sys:router:notify taxonomy. Since removed, see above.
- 2026-03-26: Added `002-calculator-leads.sql` (330f739d) alongside the
  work_calculator_lead n8n workflow. Note the duplicated `002-` prefix — it
  landed in parallel with `002-full-hwc-schema.sql`.
- 2026-03-26: Added 002-full-hwc-schema.sql — full production schema with JT reference tables, cost catalog, project state, estimates, leads, daily logs, workflow log, and views
