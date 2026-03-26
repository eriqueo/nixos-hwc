# domains/business/

## Purpose

Business services including OCR processing, receipt management, and future invoicing/CRM capabilities. Designed with fail-graceful principles and stub services when dependencies are missing.

## Boundaries

- **Manages**: Estimator PWA, Remodel API, Receipts OCR service, business data processing, Paperless-NGX (document management), Firefly III (personal finance)
- **Does NOT manage**: Database hosting (→ `domains/data/`), general file storage (→ `domains/data/storage/`)

## Structure

```
domains/business/
├── index.nix           # Domain aggregator
├── README.md           # This file
├── estimator/          # Heartwood Estimate Assembler PWA
│   └── index.nix
├── paperless/          # Paperless-NGX document management
│   ├── index.nix       # Options definitions
│   ├── sys.nix         # System packages (tesseract, poppler)
│   ├── scripts/
│   │   └── setup-paperless.sh  # API setup: tags, doc types, correspondents, fields
│   └── parts/
│       ├── config.nix      # Container configuration
│       └── directories.nix # Storage directory structure
├── firefly/            # Firefly III personal finance + Pico mobile app
│   ├── index.nix       # Options definitions
│   ├── sys.nix         # PostgreSQL grants
│   └── parts/
│       └── config.nix  # Container configuration
└── parts/
    ├── receipts-ocr.nix  # OCR service implementation
    └── api.nix           # Remodel API (FastAPI)
```

### Workspace Layout (`workspace/business/`)

```
workspace/business/
├── estimator-pwa/         # React app (Vite build)
│   ├── dist/              # Built output served by Caddy
│   ├── scripts/           # export_catalog.sh
│   └── src/data/          # catalog_export.json
├── estimate-automation/   # Estimation pipeline (data, docs, tests)
├── remodel-api/           # FastAPI backend
├── bathroom-calculator/   # Calculator PWA (Vite build)
├── migrate_catalog.py     # SQLite → Postgres migration script
├── catalog.db             # SQLite cost data (source of truth)
└── schema.sql             # Postgres schema reference
```

## Configuration

### Estimator PWA

```nix
hwc.business.estimator = {
  enable = true;
  distDir = "/home/eric/.nixos/workspace/business/estimator-pwa/dist";
  port = 13443;  # Pre-allocated, outside hwc-publish range
};
```

Access: `https://hwc.ocelot-wahoo.ts.net:13443`

Rebuild steps:
```bash
cd ~/.nixos/workspace/business/estimator-pwa
./scripts/export_catalog.sh   # After catalog.db changes
npm install && npm run build
sudo systemctl reload caddy
```

### Enable Receipts OCR

```nix
hwc.business.receiptsOcr = {
  enable = true;
  port = 8001;

  ollama = {
    enable = true;
    url = "http://localhost:11434";
    model = "llama3.2";
  };

  storageRoot = "/mnt/hot/receipts";
  confidenceThreshold = 0.7;
};
```

### Business API

```nix
hwc.business.api = {
  enable = true;
  service = {
    port = 8000;
    autoStart = true;
  };
};
```

## Deployment

### Receipts OCR

Source code expected at:
```
~/.nixos/workspace/hwc/receipt_pipeline/
├── src/
│   ├── receipt_ocr_service.py
│   └── config.py
└── database/
    └── schema.sql
```

Deploy steps:
```bash
sudo systemctl restart receipts-ocr-setup
sudo systemctl restart receipts-ocr-db-init
sudo systemctl restart receipts-ocr
curl http://localhost:8001/health
```

If source not deployed, service returns stub response with deployment instructions.

## Systemd Units

- `receipts-ocr-setup.service` - Deploys code from workspace
- `receipts-ocr.service` - Main FastAPI service
- `receipts-ocr-db-init.service` - Database initialization

## Log Files

| File | Purpose |
|------|---------|
| `/var/log/hwc/receipts-ocr.log` | Service runtime |
| `/var/log/hwc/receipts-ocr-setup.log` | Deployment |
| `/var/log/hwc/receipts-ocr-db.log` | Database init |

## Changelog

- 2026-03-26: Added migrate_catalog.py (SQLite → Postgres migration), estimate-automation moved to workspace/business/
- 2026-03-25: Added Paperless setup script for Heartwood Craft (tags, doc types, correspondents, custom fields)
- 2026-03-24: Fixed workspace path in api.nix (hwc/remodel_web_app → business/remodel-api), updated README structure and deployment paths
- 2026-03-23: Consolidated business domain - moved estimator from webapps, workspace reorganized to workspace/business/
- 2026-03-04: Namespace migration hwc.server.containers.{paperless,firefly} → hwc.business.*
- 2026-03-04: Moved paperless and firefly containers from domains/server/containers/ into domains/business/containers/
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2026-02-22: Initial domain implementation
