# domains/business/firefly/

## Purpose

Firefly III personal finance manager running as a Podman container, with optional Firefly-Pico mobile companion app and a Workbench Finance explorer. Provides budgeting, transaction tracking, full-history recurring-payment review, and guarded transaction metadata edits.

## Boundaries

- **Manages**: Firefly III + Firefly-Pico containers, the Firefly Explorer Unix-socket service, env file generation from agenix secrets, DB grants, firewall rules
- **Does NOT manage**: PostgreSQL (→ `domains/data/databases/`), reverse proxy TLS termination (→ `domains/networking/`), secret declarations (→ `domains/secrets/`)

## Structure

```
domains/business/firefly/
├── index.nix          # Option definitions + imports
├── sys.nix            # PostgreSQL database grants
├── README.md          # This file
└── parts/
    ├── config.nix     # Container definitions, storage, systemd deps, firewall, validation
    ├── automation.nix # firefly-cron + firefly-digest timers
    └── explorer.nix   # Root-only socket + hardened Workbench Finance service
```

## Namespace

`hwc.business.firefly.*`

## Configuration

```nix
hwc.business.firefly = {
  enable = true;

  images = {
    core = "docker.io/fireflyiii/core:version-6.6.6";
    pico = "cioraneanu/firefly-pico:1.10.1";
    importer = "docker.io/fireflyiii/data-importer:version-2.3.4";
  };

  settings = {
    appUrl = "https://firefly.hwc.iheartwoodcraft.com";
    timezone = "America/Denver";
    locale = "en_US";
    trustedProxies = "**";          # Safe behind Tailscale
  };

  pico = {
    enable = true;                  # Enabled by default
    appUrl = "https://firefly-pico.hwc.iheartwoodcraft.com";
    fireflyUrl = "http://firefly:8080";  # Container-internal
  };

  explorer = {
    enable = true;
    appUrl = "https://firefly-explorer.hwc.iheartwoodcraft.com";
    assetAccountId = 12;
    accountName = "Dad - Checking";
    historyStart = "2019-08-19";
    allowedLogin = "eriqueo@github";
    patFile = "/run/agenix/firefly-explorer-pat";
  };

  database = {
    host = "10.89.0.1";            # media-network gateway
    port = 5432;
    name = "firefly";
    picoName = "firefly_pico";
    user = "eric";
  };

  storage = {
    dataDir = "/mnt/apps/firefly";
    uploadDir = "/mnt/apps/firefly/upload";
  };

  reverseProxy = {
    corePort = 10443;              # External TLS
    coreInternalPort = 8085;       # Internal HTTP
    picoPort = 11443;
    picoInternalPort = 8086;
  };

  network.mode = "media";

  resources.core = { memory = "1g"; cpus = "1.0"; };
  resources.pico = { memory = "512m"; cpus = "0.5"; };
};
```

## Dependencies

- **PostgreSQL** (`hwc.data.databases.postgresql.enable`) — auto-registers `firefly` and `firefly_pico` databases
- **agenix secret**: `firefly-app-key` (Laravel APP_KEY, written to env file at container start)
- **agenix secret**: `firefly-explorer-pat` (dedicated personal access token; `root:secrets`, mode `0440`)
- **media-network** — both containers join `media` Podman network by default

## Access

| Service | URL | Internal Port |
|---------|-----|---------------|
| Firefly III | `https://firefly.hwc.iheartwoodcraft.com` | 8085 |
| Firefly-Pico | `https://firefly-pico.hwc.iheartwoodcraft.com` | 8086 |
| Data Importer | `https://firefly-import.hwc.iheartwoodcraft.com` | 8087 |
| Workbench Finance | `https://firefly-explorer.hwc.iheartwoodcraft.com` | root-only Unix socket |

Firewall rules auto-open internal ports on `tailscale0` interface.

## Systemd Units

- `podman-firefly.service` — main Firefly III container (generates env file with APP_KEY + STATIC_CRON_TOKEN in preStart)
- `podman-firefly-pico.service` — Pico mobile companion (depends on firefly)
- `podman-firefly-importer.service` — data importer (CSV/SimpleFIN; stateless, OAuth client authorized per browser session)
- `firefly-cron.timer` — daily 03:10 hit on `/api/v1/cron/<token>` (recurring transactions, bill warnings, auto-budgets fire nowhere without this)
- `firefly-digest.timer` — daily 07:15 finance digest (balances, bills due 7d, yesterday's transactions) → hwc-notify `topic=finance` → #hwc-alerts. Skips with a journal note until a PAT exists at `/run/agenix/firefly-pat` (drop `firefly-pat.age` in `domains/secrets/parts/services/` to arm it).
- `firefly-explorer.socket` — `/run/firefly-explorer.sock`, `root:root` mode `0600`; only root-run Caddy can connect.
- `firefly-explorer.service` — immutable explorer package; validates its token, Firefly account, UI assets, and tailscaled socket before serving. Every API request is authorized with Tailscale WhoIs. Split groups remain read-only; writes are limited to existing category/expense-account ids and existing tags.

## Changelog

- 2026-09-21: Pinned Explorer `0605857`: serve current HTML without conditional caching, since Nix-normalized mtimes can otherwise return stale 304 responses and reference removed JavaScript builds. Static asset caching, Tailscale API checks, and finance data are unchanged.
- 2026-09-16: Pinned Firefly Explorer fix `90a8a587`: tailscaled LocalAPI requires `Host: local-tailscaled.sock` even over its Unix socket. The original package used `localhost`, so the deployed authorization boundary failed closed with 403 for every API request. A Unix-socket regression test now watches the exact Host requirement.
- 2026-09-16: Added the Workbench Finance recurring-payment explorer from the revision-locked private `pnc-statement-pipeline` flake. The default report scans Firefly history from 2019-08-19; date controls filter visible occurrences without narrowing cadence/status analysis. Caddy reaches it only through a root-owned `0600` Unix socket, API reads require the configured Tailscale identity, and exact-fingerprint writes are limited to one journal's existing category, expense account, or tags. Added a dedicated encrypted PAT instead of sharing the digest token.
- 2026-09-15: Pinned Firefly III core 6.6.6, the minimum compatible release line for data-importer 2.3.4; importing had been blocked because core 6.4.22 was below the importer's required 6.6.0. OAuth clients and tokens must be recreated after this upgrade.
- 2026-07-13: Automation build-out — `firefly-cron-token` secret + daily cron timer, `firefly-importer` container + `firefly-import` vhost (:8087), `firefly-digest` timer posting to hwc-notify (`finance-to-alerts` route), PAT-gated until `firefly-pat.age` is provisioned.

- 2026-06-09: Access moved from dedicated tailnet ports (Firefly `:10443`, Pico `:11443`) to name-based vhosts `firefly.hwc.iheartwoodcraft.com` / `firefly-pico.hwc.iheartwoodcraft.com` under the shared `*.hwc.iheartwoodcraft.com` wildcard cert (no per-service listener / firewall hole). Both `appUrl`s updated to match — Firefly's `APP_URL` and Pico's app URL must equal the browser origin. See `domains/networking/README.md`.
- 2026-03-25: Created README per Law 12
- 2026-03-04: Namespace migration hwc.server.containers.firefly → hwc.business.firefly
