# domains/business/databases/

## Purpose

Business data layer for Heartwood Craft. Manages the `hwc` PostgreSQL database schema — cost catalog, project state, estimates, leads, receipts, vendors, and workflow logs. The database engine itself is managed by `domains/data/databases/`.

## Boundaries

- **Manages**: hwc database creation (via ensureDatabases), business schema (schema.sql), catalog data migration, seed data
- **Does NOT manage**: PostgreSQL engine config (-> domains/data/databases), application-specific queries (-> n8n workflows, estimator app), JT API sync logic (-> domains/system/mcp/parts/jt.nix)

## Structure

```
domains/business/databases/
├── index.nix           # Module: hwc.business.databases.* (database provisioning)
├── schema.sql          # Full business schema (690 lines, 15+ tables, views, triggers)
├── catalog.db          # SQLite catalog (source for migration to Postgres)
├── migrate_catalog.py  # Migration script: SQLite -> Postgres catalog_items table
└── README.md
```

## Configuration

```nix
hwc.business.databases.enable = true;  # In machines/server/config.nix
```

## Schema Sections

1. JT Reference Tables (cost codes, cost types, units — seeded with actual JT IDs)
2. Cost Catalog (trade rates, catalog items with formulas/triggers)
3. Project State (per-project key-value measurements and conditions)
4. Estimates (versioned assembled output with JSON snapshots)
5. Calculator Leads (public website calculator submissions)
6. Workflow Log (n8n action audit trail)
7. Views (pipeline_summary, lead_funnel, channel_roi)
8. Vendors (with OCR-friendly name variants)
9. Expense Categories (linked to JT cost codes)
10. Receipts OCR Pipeline (receipt processing, line items, review queue)

## Manual Setup Steps

After enabling and rebuilding:

1. Apply schema: `sudo -u postgres psql -d hwc -f ~/.nixos/domains/business/databases/schema.sql`
2. Migrate catalog: `cd ~/.nixos/domains/business/databases && python3 migrate_catalog.py`
3. Verify: `sudo -u postgres psql -d hwc -c "\dt public.*"`

## Changelog

- 2026-04-12: Created index.nix module (hwc.business.databases.*), wired into business domain
- 2026-03-24: Granted n8n postgres user access to hwc schema
- 2026-03-23: Created hwc schema with calculator_leads and daily_logs tables
