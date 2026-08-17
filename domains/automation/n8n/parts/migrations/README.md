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
  002-calculator-leads.sql   # hwc.calculator_leads for the work_calculator_lead workflow
  002-full-hwc-schema.sql    # Full production schema: all 11 tables, 5 views, seed data
```

Note the duplicated `002-` prefix: `002-calculator-leads.sql` and
`002-full-hwc-schema.sql` were authored independently and collide. The numbering is
descriptive, not an applied sequence — apply by name, not by number.

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
- 2026-08-17: Structure block corrected — `002-calculator-leads.sql` has been here since 2026-03-26 without appearing in the listing; added the `002-` collision note.
- 2026-07-07: `fbd92674` — deleted `003-notification-events.sql` (-29) as part of the Slack/gotify eradication. The live `hwc.notification_events` table was dropped in the same change; it had zero readers.
- 2026-03-31: `17b9283b` — added `003-notification-events.sql` (+29). Retired 3 months later, above.
- 2026-03-26: `330f739d` — added `002-calculator-leads.sql` (+58), the `hwc.calculator_leads` archive table for the `work_calculator_lead` workflow.
- 2026-03-26: Added 002-full-hwc-schema.sql — full production schema with JT reference tables, cost catalog, project state, estimates, leads, daily logs, workflow log, and views
