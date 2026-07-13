# domains/business/firefly/

## Purpose

Firefly III personal finance manager running as a Podman container, with optional Firefly-Pico mobile companion app. Provides budgeting, transaction tracking, and financial reporting via web UI.

## Boundaries

- **Manages**: Firefly III + Firefly-Pico containers, env file generation from agenix secrets, DB grants, firewall rules
- **Does NOT manage**: PostgreSQL (→ `domains/data/databases/`), reverse proxy TLS termination (→ `domains/networking/`), secret declarations (→ `domains/secrets/`)

## Structure

```
domains/business/firefly/
├── index.nix          # Option definitions + imports
├── sys.nix            # PostgreSQL database grants
├── README.md          # This file
└── parts/
    ├── config.nix     # Container definitions, storage, systemd deps, firewall, validation
    └── automation.nix # firefly-cron + firefly-digest timers
```

## Namespace

`hwc.business.firefly.*`

## Configuration

```nix
hwc.business.firefly = {
  enable = true;

  images = {
    core = "docker.io/fireflyiii/core:latest";
    pico = "cioraneanu/firefly-pico:latest";
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
- **media-network** — both containers join `media` Podman network by default

## Access

| Service | URL | Internal Port |
|---------|-----|---------------|
| Firefly III | `https://firefly.hwc.iheartwoodcraft.com` | 8085 |
| Firefly-Pico | `https://firefly-pico.hwc.iheartwoodcraft.com` | 8086 |
| Data Importer | `https://firefly-import.hwc.iheartwoodcraft.com` | 8087 |

Firewall rules auto-open internal ports on `tailscale0` interface.

## Systemd Units

- `podman-firefly.service` — main Firefly III container (generates env file with APP_KEY + STATIC_CRON_TOKEN in preStart)
- `podman-firefly-pico.service` — Pico mobile companion (depends on firefly)
- `podman-firefly-importer.service` — data importer (CSV/SimpleFIN; stateless, PAT pasted per session in its UI)
- `firefly-cron.timer` — daily 03:10 hit on `/api/v1/cron/<token>` (recurring transactions, bill warnings, auto-budgets fire nowhere without this)
- `firefly-digest.timer` — daily 07:15 finance digest (balances, bills due 7d, yesterday's transactions) → hwc-notify `topic=finance` → #hwc-alerts. Skips with a journal note until a PAT exists at `/run/agenix/firefly-pat` (drop `firefly-pat.age` in `domains/secrets/parts/services/` to arm it).

## Changelog

- 2026-07-13: Automation build-out — `firefly-cron-token` secret + daily cron timer, `firefly-importer` container + `firefly-import` vhost (:8087), `firefly-digest` timer posting to hwc-notify (`finance-to-alerts` route), PAT-gated until `firefly-pat.age` is provisioned.

- 2026-06-09: Access moved from dedicated tailnet ports (Firefly `:10443`, Pico `:11443`) to name-based vhosts `firefly.hwc.iheartwoodcraft.com` / `firefly-pico.hwc.iheartwoodcraft.com` under the shared `*.hwc.iheartwoodcraft.com` wildcard cert (no per-service listener / firewall hole). Both `appUrl`s updated to match — Firefly's `APP_URL` and Pico's app URL must equal the browser origin. See `domains/networking/README.md`.
- 2026-03-25: Created README per Law 12
- 2026-03-04: Namespace migration hwc.server.containers.firefly → hwc.business.firefly
