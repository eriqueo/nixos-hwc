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
    └── config.nix     # Container definitions, storage, systemd deps, firewall, validation
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
    appUrl = "https://hwc.ocelot-wahoo.ts.net:10443";
    timezone = "America/Denver";
    locale = "en_US";
    trustedProxies = "**";          # Safe behind Tailscale
  };

  pico = {
    enable = true;                  # Enabled by default
    appUrl = "https://hwc.ocelot-wahoo.ts.net:11443";
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
| Firefly III | `https://hwc.ocelot-wahoo.ts.net:10443` | 8085 |
| Firefly-Pico | `https://hwc.ocelot-wahoo.ts.net:11443` | 8086 |

Firewall rules auto-open internal ports on `tailscale0` interface.

## Systemd Units

- `podman-firefly.service` — main Firefly III container (generates env file with APP_KEY in preStart)
- `podman-firefly-pico.service` — Pico mobile companion (depends on firefly)

## Changelog

- 2026-03-25: Created README per Law 12
- 2026-03-04: Namespace migration hwc.server.containers.firefly → hwc.business.firefly
