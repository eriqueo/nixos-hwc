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
├── export_calculator_json.py    # Export DB → calculator-bathroom.json for website calculator
├── export_estimator_data.py     # Export DB → tradeRates.json, templates.json, catalog_export.json
├── CATALOG_NAMING_CONVENTION.md # Canonical catalog item naming rule
├── migrate_canonical.sql        # Adds canonical naming columns to catalog_items
├── populate_assembly_logic.py   # Copies assembler.js add() logic onto catalog_items
├── seed_catalog.py              # Seeds catalog_items from canonical_catalog_FINAL.csv
├── migrations/
│   ├── 001-catalog-schema-split.sql   # catalog_items / assembly_rules / estimate_line_items split
│   └── 002-estimator-site-visit.sql   # Site-visit catalogue repair (see Changelog)
└── README.md
```

Roles: the primary login role (`cfg.user`) is declared once for the cluster in
`domains/data/databases/index.nix`. This module declares only `business_user`
(a grantee in `schema.sql` and migration 001). It adds no postStart grants and
no per-database backup registration; `hwc` is covered by the borg pre-hook's
nightly `pg_dumpall`.

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

- 2026-10-07: Added `migrations/002-estimator-site-visit.sql` (ad7d89e3), an
  idempotent catalogue repair that leaves existing rates unchanged. It rewrites
  `assembly_rules.condition_trigger` for shower, niche, tub and tile rules;
  sets niche rule 26 `waste_factor = 1`; gates material purchases on new
  `include_*_material != "no"` flags while installation follows scope; and
  inserts site-verified panel-shower, vinyl/Marmoleum flooring and shower-door
  items with bathroom assembly rules. Rebuild JSON with
  `export_estimator_data.py` after applying it.
- 2026-08-28: Removed the four `$PSQL` GRANT lines from `postgresql.postStart`
  (never ran: `$PSQL` is undefined there) and the per-database backup
  registration (postgresql-db-backup retired 2026-08-26). Declared
  `business_user` via `ensureUsers` (e82ca994, 53e84228).
- 2026-05-01: Added export scripts, estimate_templates table, 70 catalog items with Craftsman/JT rates
- 2026-04-12: Created index.nix module (hwc.business.databases.*), wired into business domain
- 2026-03-24: Granted n8n postgres user access to hwc schema
- 2026-03-23: Created hwc schema with calculator_leads and daily_logs tables
