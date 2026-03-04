# domains/server/

## Purpose

Residual server domain — provides shared infrastructure that hasn't been migrated
to purpose-specific domains yet. Most server services have been moved to their
respective domains during the DDD migration.

## Boundaries

- **Manages**: `hwc.server.enable`, `hwc.server.role` options, Caddy container (stub), shared container directory structure
- **Does NOT manage**: Media (→ `domains/media/`), Networking (→ `domains/networking/`), Data (→ `domains/data/`), Monitoring (→ `domains/monitoring/`), AI (→ `domains/ai/`), Gaming (→ `domains/gaming/`), Business (→ `domains/business/`), Automation (→ `domains/automation/`)

## Structure

```
domains/server/
├── index.nix           # Domain aggregator
├── options.nix         # hwc.server.enable, hwc.server.role
└── containers/
    ├── index.nix       # Imports: legacy rename, directories, caddy
    ├── _shared/        # Re-export wrappers (pure.nix, infra.nix, arr-config.nix)
    │                   # Canonical implementations are in lib/
    └── caddy/          # Caddy container (stub — kept for option compatibility)
```

## Migration Status (DDD Phase 0–10)

All services migrated out of domains/server/:

| Service Group | Migrated To |
|---|---|
| Media containers (sonarr, radarr, etc.) | `domains/media/` |
| Networking (reverseProxy, gluetun, pihole) | `domains/networking/` |
| Data (databases, backup, storage, couchdb) | `domains/data/` |
| Monitoring (prometheus, grafana, etc.) | `domains/monitoring/` |
| Automation (n8n) | `domains/automation/` |
| Gaming (retroarch, webdav) | `domains/gaming/` |
| Business (paperless, firefly, receipts-ocr) | `domains/business/` |
| AI (ollama, open-webui, mcp, ai-bible) | `domains/ai/` |

## Namespace

- `hwc.server.enable` — enables server workloads
- `hwc.server.containers.*` — still used by moved container modules (namespace unchanged)
- `hwc.server.native.*` — still used by moved native modules (namespace unchanged)
- `hwc.server.reverseProxy.*` — defined in `domains/networking/reverseProxy.nix`

## Changelog

- 2026-03-04: Removed hwc.server.role option and isPrimary indirection
- 2026-03-04: Removed stale domains/server/media/ (orphaned stub, never imported)
- 2026-03-04: DDD migration complete — all services moved to dedicated domains; native/ deleted; README updated
- 2026-02-26: Created README per Law 12
