# domains/business/paperless/

## Purpose

Paperless-NGX document management system running as a Podman container. Provides OCR-powered document ingestion, indexing, and archival with a web UI accessible via reverse proxy.

## Boundaries

- **Manages**: Paperless-NGX container, consume/export/staging directories, the
  safe `email-to-paperless` PDF intake command, env file generation from agenix
  secrets, cleanup timers
- **Does NOT manage**: PostgreSQL or Redis (→ `domains/data/databases/`), reverse proxy routing (→ `domains/networking/`), secret declarations (→ `domains/secrets/`)

## Structure

```
domains/business/paperless/
├── index.nix              # Option definitions + imports
├── sys.nix                # System packages + email-to-paperless command
├── README.md              # This file
├── parts/
    ├── config.nix         # Paperless + Tika/Gotenberg containers, env generation, cleanup timer
    ├── directories.nix    # tmpfiles rules for storage directories (SOLE producer)
    └── receipts.nix       # IMAP proxy (mail ingest) + phone-receipts → consume mover
└── scripts/
    ├── email-to-paperless.py # deterministic, text-only email PDF renderer
    └── setup-paperless.sh    # one-time API setup helper
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
  consumer.recursive = true;        # scan consume/ subdirectories
  consumer.subdirsAsTags = true;    # consume/a/b/x.pdf → tags a, b

  officeIngest.enable = true;       # Tika + Gotenberg sidecars (.doc/.docx/.odt/.rtf/.ppt)
  officeIngest.tikaImage = "docker.io/apache/tika:3.3.1.0";
  officeIngest.gotenbergImage = "docker.io/gotenberg/gotenberg:8.7.0";

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
- `podman-paperless-tika.service` / `podman-paperless-gotenberg.service` — Office-ingest sidecars (ordered before paperless, not required by it)
- `paperless-cleanup.service` / `paperless-cleanup.timer` — daily staging/export cleanup

## Changelog

- 2026-09-16: `ocr.continueOnSoftRenderError` (on by default) sets
  `PAPERLESS_OCR_USER_ARGS={"continue_on_soft_render_error":true}`. Ghostscript
  10.05.1 refuses to write a PDF/A copy of a file that breaks PDF/A rules — two
  Cancer Cell papers use images with `Interpolate true` — and ocrmypdf then failed
  the whole import, so the document never existed. Only the archive copy can now
  differ from the source; the original is stored either way.

- 2026-09-16: Upgraded to paperless-ngx 3.1.3 (Gotenberg 8.34, the version its
  compose file pins). 2.14's Ghostscript 10.03.1 crashed making PDF/A copies of
  some PDFs. The env file now sets `PAPERLESS_DBENGINE=postgresql`, which v3
  requires, and renames `CONSUMER_POLLING` to `CONSUMER_POLLING_INTERVAL`. Two new
  options keep v2 behaviour against changed v3 defaults: `ocr.archiveFileGeneration
  = "always"` and `consumer.deleteDuplicates = true`. v3 migrates only from 2.20.15,
  so the database was first migrated by a one-off 2.20.15 container.

- 2026-09-16: Office-document ingest and folder tags. Paperless parses only PDFs
  and images and skips other files without an error, so `.doc`/`.docx`/`.odt`/`.rtf`/`.ppt`
  in the consume dir never became documents. `officeIngest` adds Tika (text and
  metadata) and Gotenberg (PDF render) as sidecars on media-network, reached by
  container DNS with no host ports. Paperless is ordered after them but does not
  `require` them: a failed sidecar stops Office imports, not the document store.
  Gotenberg runs with JavaScript off and a `file:///tmp` allow-list because its
  chromium route renders untrusted `.eml`. `consumer.recursive` and
  `consumer.subdirsAsTags` let a bulk import carry its source folders as tags;
  the receipts mover and `email-to-paperless` both write to the consume root, so
  they gain no tags.
- 2026-09-14: Added `email-to-paperless` for aerc's opened-message `p` key. It
  parses mail without running HTML, renders deterministic PDF bytes for checksum
  dedupe, writes in staging, and atomically renames into consume. The source mail
  remains unchanged. The server's one Borg job now includes `storage.mediaDir`,
  closing the gap between this README's CRITICAL/backup claim and the actual
  source list; PostgreSQL state continues through the existing dump source.
- 2026-08-20: `paperless-cleanup` no longer deletes its own bind-mount sources. `find <staging> <export> -type d -empty -delete` treats its start points as matches, and both dirs are normally empty, so the nightly timer removed `/mnt/hot/documents/{staging,export}` — after which podman failed the next container start with `statfs /mnt/hot/documents/export: no such file or directory`. It only stayed invisible because a *running* container holds the mount; the crash surfaced whenever paperless was restarted (2026-07-06, 1600+ restarts; again 2026-08-20 on the vhost rebuild). Fixed with `-mindepth 1`, which keeps the prune inside each dir while still collecting empty subdirectories — the same fix `domains/data/storage/parts/cleanup.nix` already carries after the identical shape unlinked a bind-mount target under slskd. **The 2026-07-06 fix was tmpfiles rules, and they were dead code twice over:** they duplicated `parts/directories.nix`, so systemd-tmpfiles kept the first line, logged `Duplicate line for path ..., ignoring` and never applied the `0775` they asked for (effective mode was and remains `0750`); and tmpfiles runs at boot/activation while the deleter runs nightly, so the cadence could not have defended against it anyway. That duplicate producer is deleted; `directories.nix` is now the sole declarer of these paths and carries the rationale. Regression check: `systemctl start paperless-cleanup.service` must leave `/mnt/hot/documents/{export,staging}` present — that check failed before this commit.
- 2026-08-20: Moved off the `/docs` subpath onto `paperless.hwc.iheartwoodcraft.com`. Three settings had to move together, and the reason is Django rather than routing: `PAPERLESS_URL`, `PAPERLESS_CORS_ALLOWED_ORIGINS` and `PAPERLESS_CSRF_TRUSTED_ORIGINS` all derive from one `paperlessUrlBase`, which previously pointed at `reverseProxy.domain` (the tailnet root host). Django checks the request Origin against the CSRF list on every unsafe method, so serving paperless under a name absent from that list leaves **reads working and every write failing** — logins, uploads, tag edits — with a 200 on `GET /` the whole time. Verification for this app is therefore an authenticated POST, not a status code. `reverseProxy.path` now defaults to `""` and `PAPERLESS_FORCE_SCRIPT_NAME` is emitted only when it is non-empty, so the prefix deployment stays available without a code change; when set it must match the route's `path` exactly, since Django prefixes every generated URL with it.
- 2026-07-13: Receipt/statement intake — `paperless-imap-proxy` (socat, Proton Bridge 127.0.0.1:1143 → podman gateway 10.89.0.1:1143) so the container's mail fetcher can poll `eric@iheartwoodcraft.com` mailboxes; `paperless-receipts-mover` path unit + 15-min sweep moving photo/PDF drops from the phone-synced `/mnt/vaults/inbox-mobile/receipts/` into the consume dir. Mail account + receipt/statement rules configured in Paperless via API (DB-owned, not Nix).
- 2026-03-25: Created README per Law 12
- 2026-03-04: Namespace migration hwc.server.containers.paperless → hwc.business.paperless
