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
│   └── parts/
│       ├── config.nix      # Container configuration
│       └── directories.nix # Storage directory structure
├── firefly/            # Firefly III personal finance + Pico mobile app
│   ├── index.nix       # Options definitions
│   ├── sys.nix         # PostgreSQL grants
│   └── parts/
│       └── config.nix  # Container configuration
├── receipts-pipeline/     # Receipt OCR service (Python + FastAPI)
│   ├── src/               # Python source
│   ├── n8n-workflows/     # n8n intake workflow JSON
│   └── monitoring/        # Health check script
├── heartwood_mcp_server.md     # System 7: Heartwood MCP Server spec
├── n8n_workflow_registry.md    # n8n workflow registry — all automation workflows
├── paperless_integration_spec.md # Paperless-ngx integration + receipt pipeline spec
└── parts/
    ├── receipts-ocr.nix  # OCR NixOS service definition
    └── api.nix           # Remodel API (FastAPI)
```

### Workspace Layout

```
workspace/business/
├── estimator-pwa/         # React app (Vite build)
│   ├── dist/              # Built output served by Caddy
│   ├── scripts/           # export_catalog.sh
│   └── src/data/          # catalog_export.json
├── remodel-api/           # FastAPI backend
├── catalog.db             # SQLite cost data (source of truth)
└── schema.sql             # ALL business Postgres tables (shared)
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

Source code at `~/.nixos/domains/business/receipts-pipeline/src/`.
Schema is part of the shared `workspace/business/schema.sql` (sections 8-12).

Deploy steps:
```bash
sudo systemctl restart receipts-ocr-setup
sudo systemctl restart receipts-ocr
curl http://localhost:8001/health
```

If source not deployed, service returns stub response with deployment instructions.

## Systemd Units

- `receipts-ocr-setup.service` - Deploys code from workspace
- `receipts-ocr.service` - Main FastAPI service (port 8001)

## Changelog

- 2026-03-25: Added n8n workflow registry — all automation workflows with specs, MCP migration path
- 2026-03-25: Added Paperless-ngx integration spec — document management, receipt pipeline, Claude job matching, Firefly sync plan
- 2026-03-25: Added Heartwood MCP Server spec (System 7) — unified MCP interface to JT, Paperless, Firefly, and n8n compound operations
- 2026-03-25: Consolidated receipts OCR pipeline into business domain — source at domains/business/receipts-pipeline/, schema merged into shared schema.sql, job_id→project_id, removed standalone db-init service
- 2026-03-24: Calculator lead webhook fully operational - creates JT Account/Contact/Location/Job with custom fields, archives to Postgres, notifies Slack. See domains/automation/n8n/parts/workflows/README.md for workflow docs.
- 2026-03-24: Fixed workspace path in api.nix (hwc/remodel_web_app → business/remodel-api), updated README structure and deployment paths
- 2026-03-23: Consolidated business domain - moved estimator from webapps, workspace reorganized to workspace/business/
- 2026-03-04: Namespace migration hwc.server.containers.{paperless,firefly} → hwc.business.*
- 2026-03-04: Moved paperless and firefly containers from domains/server/containers/ into domains/business/containers/
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2026-02-22: Initial domain implementation
