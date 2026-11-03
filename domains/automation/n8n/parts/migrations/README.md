# migrations

## Purpose
SQL migration files for the `hwc` PostgreSQL database. Applied in order against the `hwc` database on the homeserver.

## Boundaries
- Business tables live in `hwc`; the retained prototype and calendar logger use explicit `public` tables.
- Migrations are numbered sequentially: `NNN-description.sql`
- Each migration is idempotent (`CREATE TABLE IF NOT EXISTS`, `ON CONFLICT DO NOTHING`)

## Structure
```
migrations/
  001-estimates-table.sql    # Initial estimates table (early prototype)
  002-full-hwc-schema.sql    # Full production schema: all 11 tables, 5 views, seed data
  004-workflow-run-metadata.sql # Nullable public calendar metadata; shared role transaction
```

## Applying Migrations

The managed workflow database applies004 in the bounded role transaction before
column grants and n8n startup. It preserves existing rows and old readers; code
recovery retains the new column and any later history. Existing unrelated
migrations below remain operator-owned and are not replayed by that provisioner.
```bash
sudo -u postgres psql -d hwc -f 002-full-hwc-schema.sql
```

If the database doesn't exist yet:
```bash
sudo -u postgres createdb hwc
sudo -u postgres psql -d hwc -f 002-full-hwc-schema.sql
```

## Changelog
- 2026-11-03: Add idempotent public workflow_runs.metadata JSONB preparation and reject an incompatible existing column.
- 2026-09-08: Removed the unused event migration. Event Scout owns its versioned
  PostgreSQL schema and case history; n8n no longer owns event data.
- 2026-09-07: Added 003-event-case-ledger.sql — AUTO-MANAGED 180-day event case ledger with versioned append-only curation judgments, atomic Discord/calendar reservations, append-only human actions, and bounded cleanup.
- 2026-03-26: Added 002-full-hwc-schema.sql — full production schema with JT reference tables, cost catalog, project state, estimates, leads, daily logs, workflow log, and views
