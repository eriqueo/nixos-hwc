# workspace/business/

Consolidated business application source code and data.

## Structure

```
workspace/business/
├── estimator-pwa/      # Heartwood Estimate Assembler (React/Vite)
│   ├── dist/           # Built output served by Caddy on :13443
│   ├── scripts/        # export_catalog.sh
│   └── src/data/       # catalog_export.json (generated)
├── remodel-api/        # Bathroom Remodel API (FastAPI)
│   ├── routers/
│   ├── engines/
│   └── Dockerfile
├── catalog.db          # SQLite cost catalog (source of truth, read-only)
├── schema.sql          # Postgres schema (hwc database, public schema)
├── migrate_catalog.py  # Idempotent SQLite → Postgres migration script
└── README.md
```

## Estimator PWA

Static React PWA for generating bathroom remodel estimates.

**URL**: `https://hwc.ocelot-wahoo.ts.net:13443`

**Build**:
```bash
cd estimator-pwa
./scripts/export_catalog.sh   # After catalog.db changes
npm install && npm run build
sudo systemctl reload caddy
```

**NixOS Config**: `hwc.business.estimator` in `machines/server/config.nix`

## Remodel API

FastAPI backend for the bathroom remodel wizard (not yet deployed).

**NixOS Config**: `hwc.business.api` (disabled)

## Catalog

SQLite database containing cost items, labor rates, and formulas.

**Export Pipeline**:
```
catalog.db → export_catalog.sh → src/data/catalog_export.json → npm run build
```

Run export manually after updating catalog, then rebuild PWA.

## Postgres Catalog

The SQLite catalog is mirrored into the `hwc` Postgres database for use by
the MCP server, n8n workflows, and future apps. The SQLite file remains the
source of truth — Postgres is a copy.

**Tables populated**: `catalog_items` (62 rows), `trade_rates` (9 rows)

**Migration**:
```bash
python3 workspace/business/migrate_catalog.py
```

The script is idempotent (`ON CONFLICT DO UPDATE`). Safe to re-run after
catalog.db changes.

## Changelog

- 2026-03-26: Added migrate_catalog.py; seeded hwc Postgres from catalog.db (62 items, 9 trades)

## Related

- `domains/business/` — NixOS module definitions
- `~/600_shared/business/exports/` — JSON exports for laptop sync
- `~/600_shared/business/reports/` — Generated PDF estimates
