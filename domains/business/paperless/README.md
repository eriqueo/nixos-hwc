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
    ├── directories.nix    # tmpfiles rules for storage directories
    └── receipts.nix       # IMAP proxy (mail ingest) + phone-receipts → consume mover
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

  reverseProxy.path = "";   # vhost at paperless.<vhostDomain>; no prefix

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

- 2026-08-20: Moved off the `/docs` subpath onto `paperless.hwc.iheartwoodcraft.com`. Three settings had to move together, and the reason is Django rather than routing: `PAPERLESS_URL`, `PAPERLESS_CORS_ALLOWED_ORIGINS` and `PAPERLESS_CSRF_TRUSTED_ORIGINS` all derive from one `paperlessUrlBase`, which previously pointed at `reverseProxy.domain` (the tailnet root host). Django checks the request Origin against the CSRF list on every unsafe method, so serving paperless under a name absent from that list leaves **reads working and every write failing** — logins, uploads, tag edits — with a 200 on `GET /` the whole time. Verification for this app is therefore an authenticated POST, not a status code. `reverseProxy.path` now defaults to `""` and `PAPERLESS_FORCE_SCRIPT_NAME` is emitted only when it is non-empty, so the prefix deployment stays available without a code change; when set it must match the route's `path` exactly, since Django prefixes every generated URL with it.
- 2026-07-13: Receipt/statement intake — `paperless-imap-proxy` (socat, Proton Bridge 127.0.0.1:1143 → podman gateway 10.89.0.1:1143) so the container's mail fetcher can poll `eric@iheartwoodcraft.com` mailboxes; `paperless-receipts-mover` path unit + 15-min sweep moving photo/PDF drops from the phone-synced `/mnt/vaults/inbox-mobile/receipts/` into the consume dir. Mail account + receipt/statement rules configured in Paperless via API (DB-owned, not Nix).
- 2026-03-25: Created README per Law 12
- 2026-03-04: Namespace migration hwc.server.containers.paperless → hwc.business.paperless
