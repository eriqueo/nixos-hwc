# domains/data/couchdb/

## Purpose

CouchDB database server for Obsidian LiveSync. Runs as a native NixOS service (not containerized) with admin credentials injected from agenix secrets. Configured for single-node operation with CORS enabled for Obsidian clients.

## Boundaries

- **Manages**: CouchDB native service, config generation from secrets, health monitoring, CORS settings
- **Does NOT manage**: Reverse proxy (→ `domains/networking/`), Obsidian app config (→ `domains/home/apps/obsidian/`)

## Structure

```
domains/data/couchdb/
├── index.nix              # Options, service config, health monitor, validation
├── config-generator.nix   # Config template helper
└── README.md              # This file
```

## Namespace

`hwc.data.couchdb.*`

## Configuration

```nix
hwc.data.couchdb = {
  enable = true;

  settings = {
    port = 5984;
    bindAddress = "127.0.0.1";
    dataDir = "/var/lib/couchdb";
    maxDocumentSize = 50000000;      # 50MB for Obsidian attachments
    maxHttpRequestSize = 4294967296; # 4GB
    corsOrigins = [
      "app://obsidian.md"
      "capacitor://localhost"
      "http://localhost"
    ];
  };

  # Defaults to hwc.secrets.api paths if null
  secrets.adminUsername = null;
  secrets.adminPassword = null;

  monitoring.enableHealthCheck = true;

  reverseProxy = {
    enable = false;
    path = "/couchdb";
  };
};
```

## Details

- Runs as **eric:users** via `mkForce` (simplified permissions)
- Admin credentials written to `local.ini` at startup from agenix secrets
- Single-node mode, requires valid user for all requests
- CORS configured specifically for Obsidian LiveSync clients

## Dependencies

- **agenix secrets**: `couchdb-admin-username`, `couchdb-admin-password` (via `hwc.secrets.api`)

## Systemd Units

- `couchdb-config-setup.service` — injects secrets into `local.ini` before CouchDB starts
- `couchdb.service` — native CouchDB (NixOS module)
- `couchdb-health-monitor.service` — health check for LiveSync (manual trigger)

## Changelog

- 2026-03-25: Created README per Law 12
