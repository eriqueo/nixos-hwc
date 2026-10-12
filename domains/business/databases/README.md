# domains/business/databases/

## Purpose

Business data layer for Heartwood Craft. Manages the `hwc` PostgreSQL database schema — cost catalog, project state, estimates, leads, receipts, vendors, and workflow logs. The database engine itself is managed by `domains/data/databases/`.

## Boundaries

- **Manages**: hwc database creation (via ensureDatabases), business schema (schema.sql), catalog data migration, seed data
- **Does NOT manage**: PostgreSQL engine config (-> domains/data/databases), application-specific queries (-> n8n workflows, estimator app), JT API sync logic (-> domains/system/mcp/parts/jt.nix)

## Structure

```
domains/business/databases/
├── index.nix                    # Module: hwc.business.databases.* (database provisioning)
├── schema.sql                   # Full business schema (690 lines, 15+ tables, views, triggers)
├── catalog.db                   # SQLite catalog (source for migration to Postgres)
├── migrate_catalog.py           # Migration script: SQLite -> Postgres catalog_items table
├── migrate_canonical.sql        # Canonical-naming migration for the catalog tables
├── populate_assembly_logic.py   # Seeds assembly logic for catalog items
├── seed_catalog.py              # Seeds the catalog tables
├── CATALOG_NAMING_CONVENTION.md # Naming contract for catalog item ids
├── migrations/                  # Numbered SQL migrations applied by hand
│   ├── 001-catalog-schema-split.sql
│   └── 002-estimator-site-visit.sql
├── export_calculator_json.py    # Export DB → calculator-bathroom.json for website calculator
├── export_estimator_data.py     # Export DB → tradeRates.json, templates.json, catalog_export.json
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

## Export Scripts

Two scripts export DB data to JSON for the website calculator and internal estimator:

```bash
# Export calculator JSON (bathroom pricing → website)
python3 export_calculator_json.py
# Writes: domains/business/website/site_files/src/_data/calculator-bathroom.json

# Export estimator data (rates, catalog, templates → assembler app)
python3 export_estimator_data.py
# Writes: domains/business/estimator/app/src/data/{tradeRates,catalog_export,templates}.json
```

After exporting, rebuild the apps:
```bash
cd ../website/calculator/app && npm run build          # Calculator
sudo systemctl start estimator-build                    # Estimator
```

Or use MCP: `hwc_estimator_export` → `hwc_estimator_build`

## Key Tables

| Table | Rows | Purpose |
|-------|------|---------|
| `trade_rates` | 9 | Labor rates by trade (wage, burden, markup → computed cost/price) |
| `catalog_items` | 70 | Scope items with condition triggers, formulas, production rates |
| `estimate_templates` | 8 | Pre-configured state snapshots (4 bathroom, 4 deck) |
| `calculator_leads` | — | Website calculator form submissions |
| `projects` | — | Full project state for assembler |
| `estimates` | — | Versioned assembled line items |
| `receipts` | — | OCR receipt pipeline |

## Manual Setup Steps

After enabling and rebuilding:

1. Apply schema: `sudo -u postgres psql -d hwc < schema.sql`
2. Apply seed data: `sudo -u postgres psql -d hwc < ~/bathroom_calculator_seed.sql`
3. Verify: `sudo -u postgres psql -d hwc -c "\dt public.*"`

## Changelog

- 2026-10-07: Added `migrations/002-estimator-site-visit.sql` — an idempotent
  catalogue repair that rewrites `assembly_rules.condition_trigger` for the shower,
  tile and tub rules (quote-driven panel shower, vinyl/Marmoleum, customer purchase
  vs installation) and corrects the niche waste factor from 0.1 to 1.0. Existing
  trade rates are unchanged. Rebuild the JSON with `export_estimator_data.py`
  after applying it.
- 2026-08-28: Removed the four `$PSQL` GRANT lines from `index.nix` — none ever ran
  (`$PSQL` is undefined in the generated postgresql post-start script and `|| true`
  swallowed the command-not-found), and they were not load-bearing: `eric` is a
  cluster superuser and owns this database. Declared `business_user` via
  `ensureUsers` instead, because `schema.sql` and `migrations/001-catalog-schema-split.sql`
  grant to that role by name and it had only ever existed by hand on the live
  cluster. Dropped the `perDatabase` backup registration too — `postgresql-db-backup`
  was retired 2026-08-26, so it was dead config that read as a backup; the borg
  pre-hook's nightly `pg_dumpall` covers `hwc`.
- 2026-05-01: Added export scripts, estimate_templates table, 70 catalog items with Craftsman/JT rates
- 2026-04-12: Created index.nix module (hwc.business.databases.*), wired into business domain
- 2026-03-24: Granted n8n postgres user access to hwc schema
- 2026-03-23: Created hwc schema with calculator_leads and daily_logs tables
