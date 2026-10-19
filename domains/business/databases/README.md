# domains/business/databases/

## Purpose

Business data layer for Heartwood Craft. Manages the `hwc` PostgreSQL database schema — cost catalog, project state, estimates, leads, receipts, vendors, and workflow logs. The database engine itself is managed by `domains/data/databases/`.

## Boundaries

- **Manages**: hwc database creation (via ensureDatabases), business schema (schema.sql), catalog data migration, seed data
- **Does NOT manage**: PostgreSQL engine config (-> domains/data/databases), application-specific queries (-> n8n workflows, estimator app), JT API sync logic (-> domains/system/mcp/parts/jt.nix)

## Structure

```
domains/business/databases/
├── index.nix                      # Module: hwc.business.databases.* (database + business_user)
├── schema.sql                     # Full business schema (tables, views, triggers)
├── migrate_canonical.sql          # Canonical-schema migration
├── migrations/
│   ├── 001-catalog-schema-split.sql   # Catalog schema split (grants to business_user)
│   └── 002-estimator-site-visit.sql   # Assembly-rule repair for estimator site visits
├── catalog.db                     # SQLite catalog (source for migration to Postgres)
├── migrate_catalog.py             # Migration script: SQLite -> Postgres catalog_items table
├── seed_catalog.py                # Seed the catalog tables
├── populate_assembly_logic.py     # Populate assembly_rules condition triggers/formulas
├── export_calculator_json.py      # Export DB → calculator-bathroom.json for website calculator
├── export_estimator_data.py       # Export DB → tradeRates.json, templates.json, catalog_export.json
├── CATALOG_NAMING_CONVENTION.md   # Naming rules for catalog items
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
  assembly-rule repair for the estimator's shower/site-visit scope (condition
  triggers rewritten, the niche waste factor corrected from 0.1 to 1.0). Existing
  trade rates unchanged; rebuild the JSON with `export_estimator_data.py` after
  applying it (`ad7d89e3`).
- 2026-08-28: `business_user` is now declared here via
  `services.postgresql.ensureUsers` — this module owns it, because `schema.sql` and
  `migrations/001-catalog-schema-split.sql` grant to it by name and nothing else in
  the repo mentions it. No `ensureDBOwnership`: `eric` owns the database and its
  objects; `business_user` is only a grantee (`53e84228`).
- 2026-08-28: Deleted the four `$PSQL` GRANT lines from `postStart` and the
  per-database backup registration. `$PSQL` is undefined in the generated
  postgresql post-start script and `|| true` swallowed the command-not-found, so
  none of them ever ran — and they were not load-bearing, since `cfg.user` is both
  a superuser and the database owner. `postgresql-db-backup` was retired 2026-08-26
  (Law 15); `hwc` now rides the borg pre-hook's nightly `pg_dumpall` into
  `/var/lib/backups` (`e82ca994`).
- 2026-05-01: Added export scripts, estimate_templates table, 70 catalog items with Craftsman/JT rates
- 2026-04-12: Created index.nix module (hwc.business.databases.*), wired into business domain
- 2026-03-24: Granted n8n postgres user access to hwc schema
- 2026-03-23: Created hwc schema with calculator_leads and daily_logs tables
