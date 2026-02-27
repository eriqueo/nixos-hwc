# domains/business/

## Purpose

Business services including OCR processing, receipt management, and future invoicing/CRM capabilities. Designed with fail-graceful principles and stub services when dependencies are missing.

## Boundaries

- **Manages**: Receipts OCR service, business API endpoints, business data processing
- **Does NOT manage**: Document storage (→ Paperless-NGX in `domains/server/containers/`), database hosting (→ `domains/server/databases/`), general file storage (→ `domains/infrastructure/storage/`)

## Structure

```
domains/business/
├── index.nix           # Domain aggregator
├── options.nix         # hwc.business.* options
└── parts/
    ├── receipts-ocr.nix  # OCR service implementation
    └── api.nix           # Business API (placeholder)
```

## Configuration

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

Source code expected at:
```
~/.nixos/workspace/projects/receipts-pipeline/
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

- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2026-02-22: Initial domain implementation
