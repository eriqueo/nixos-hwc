# domains/business/paperless/

## Purpose

Paperless-NGX document management system running as a Podman container. Provides OCR-powered document ingestion, indexing, and archival with a web UI accessible via reverse proxy.

## Boundaries

- **Manages**: Paperless-NGX container, consume/export/staging directories, env file generation from agenix secrets, cleanup timers
- **Does NOT manage**: PostgreSQL or Redis (→ `domains/data/databases/`), reverse proxy routing (→ `domains/networking/`), secret declarations (→ `domains/secrets/`)

## Structure

```
domains/business/paperless/
├── index.nix              # Option definitions + imports
├── sys.nix                # System packages (tesseract, poppler-utils)
├── README.md              # This file
└── parts/
    ├── config.nix         # Container definition, env generation, DB grants, cleanup timer
    └── directories.nix    # tmpfiles rules for storage directories
```

## Namespace

`hwc.business.paperless.*`

## Configuration

```nix
hwc.business.paperless = {
  enable = true;
  image = "ghcr.io/paperless-ngx/paperless-ngx:2.14";
  port = 8102;                      # Internal HTTP port
  network.mode = "media";           # Podman network

  database = {
    host = "10.89.0.1";             # media-network gateway
    port = 5432;
    name = "paperless";
    user = "eric";
  };

  redis = {
    host = "10.89.0.1";
    port = 6379;
  };

  storage = {
    consumeDir = "/mnt/hot/documents/consume";
    exportDir = "/mnt/hot/documents/export";
    stagingDir = "/mnt/hot/documents/staging";
    mediaDir = "/mnt/media/documents/paperless";
    dataDir = "/mnt/apps/paperless/data";
  };

  ocr.languages = [ "eng" ];
  ocr.outputType = "pdfa";

  consumer.polling = 60;
  consumer.deleteOriginals = false;

  admin.user = "eric";
  admin.email = "eric@hwc.local";

  reverseProxy.path = "/docs";

  resources.memory = "4g";
  resources.cpus = "2.0";

  retention.cleanup = {
    enable = true;
    schedule = "daily";
    stagingDays = 7;
    exportDays = 30;
  };
};
```

## Dependencies

- **PostgreSQL** (`hwc.data.databases.postgresql.enable`) — auto-registers database
- **Redis** (`hwc.data.databases.redis.enable`) — used for task queue
- **agenix secrets**: `paperless-secret-key`, `paperless-admin-password`
- **media-network** — container joins `media` Podman network by default

## Storage Layout

| Path | Purpose | Retention |
|------|---------|-----------|
| `storage.mediaDir/originals` | Original uploaded documents | Indefinite + backup |
| `storage.mediaDir/archive` | OCR'd PDF/A copies | Indefinite + backup |
| `storage.mediaDir/thumbnails` | Document thumbnails | Indefinite |
| `storage.dataDir` | Search index, DB cache | Recreatable |
| `storage.consumeDir` | Drop zone for auto-import | Transient |
| `storage.stagingDir` | Pre-processing area | Cleaned after 7 days |
| `storage.exportDir` | Exported documents | Cleaned after 30 days |

## Systemd Units

- `paperless-env.service` — generates env file from agenix secrets (runs before container)
- `podman-paperless.service` — main Paperless-NGX container
- `paperless-cleanup.service` / `paperless-cleanup.timer` — daily staging/export cleanup

## Changelog

- 2026-07-13: Storage dirs (consume/export/staging/media) now declared via `systemd.tmpfiles.rules` in `parts/config.nix` — the bind-mount sources vanished from `/mnt/hot` after a reboot and podman crash-looped (1600+ restarts) with statfs errors. Same commit pinned the container image to a critical-tier version (Law 15 v12.4).
- 2026-06-02: Server tailnet rename swept through (`hwc.ocelot-wahoo.ts.net` → `hwc-server.ocelot-wahoo.ts.net`) — mechanical.
- 2026-03-25: Created README per Law 12
- 2026-03-04: Namespace migration hwc.server.containers.paperless → hwc.business.paperless
