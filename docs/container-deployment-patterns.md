# Container Deployment Patterns — nixos-hwc Reference

> Auto-generated reference for the `hwc-server` NixOS configuration.
> Source: `/home/eric/.nixos` (Charter v11.1)
> Purpose: Enable an MCP tool to deploy containers without exploring the repo at runtime.

---

## Table of Contents

1. [Repository Structure](#1-repository-structure)
2. [Container Definition Patterns](#2-container-definition-patterns)
3. [Port Allocation — Full Map](#3-port-allocation--full-map)
4. [Caddy / Reverse Proxy](#4-caddy--reverse-proxy)
5. [Secrets Management](#5-secrets-management)
6. [Systemd Service Patterns](#6-systemd-service-patterns)
7. [Domain / DNS Structure](#7-domain--dns-structure)
8. [Rebuild Process](#8-rebuild-process)
9. [Networking — Tailscale, Gluetun, Firewall](#9-networking--tailscale-gluetun-firewall)
10. [Existing Services Inventory](#10-existing-services-inventory)
11. [Common Pitfalls](#11-common-pitfalls)
12. [Step-by-Step: Adding a New Container](#12-step-by-step-adding-a-new-container)

---

## 1. Repository Structure

### Top-Level Layout

```
/home/eric/.nixos/
├── flake.nix                          # Entry point — wires pkgs, inputs, nixosConfigurations
├── secrets.nix                        # agenix recipient rules (public keys per secret)
├── machines/
│   ├── server/
│   │   ├── config.nix                 # hwc-server machine config (authoritative)
│   │   ├── hardware.nix
│   │   └── home.nix
│   └── laptop/config.nix
├── profiles/
│   ├── core.nix                       # Universal base: system + secrets + data domains
│   ├── server.nix                     # Server profile (legacy — most logic now in machine config)
│   ├── monitoring.nix
│   └── ...
├── domains/
│   ├── server/
│   │   ├── containers/                # OCI container modules
│   │   │   ├── _shared/               # Shared helpers: network, caddy, directories, pure.nix
│   │   │   ├── gluetun/               # VPN gateway
│   │   │   ├── immich/                # Photo management
│   │   │   ├── jellyseerr/            # Media requests
│   │   │   ├── sonarr/ radarr/ lidarr/ prowlarr/ readarr/  # *arr stack
│   │   │   ├── qbittorrent/ sabnzbd/ # Downloaders
│   │   │   ├── slskd/ soularr/        # Soulseek
│   │   │   ├── pinchflat/             # YouTube subscriptions
│   │   │   ├── calibre/               # Ebook library
│   │   │   ├── recyclarr/ organizr/   # Utilities
│   │   │   └── ...
│   │   └── native/                    # NixOS native services (not containers)
│   │       ├── navidrome/
│   │       ├── jellyfin/
│   │       ├── couchdb/
│   │       ├── monitoring/            # Prometheus, Grafana, Alertmanager
│   │       └── ...
│   ├── networking/
│   │   ├── reverseProxy.nix           # Caddy config renderer
│   │   ├── routes.nix                 # ALL service routes (single file)
│   │   ├── podman-network.nix         # media-network creation
│   │   ├── gluetun/                   # VPN container (networking domain view)
│   │   └── cloudflared/               # Public webhook tunnel
│   ├── secrets/
│   │   ├── index.nix                  # Aggregator + hwc.secrets.api auto-map
│   │   ├── declarations/              # Per-domain age.secrets declarations
│   │   │   ├── infrastructure.nix     # VPN, cameras, cloudflare
│   │   │   ├── services.nix           # All service API keys, passwords
│   │   │   └── ...
│   │   └── parts/                     # Encrypted .age files (binary)
│   ├── paths/
│   │   └── paths.nix                  # ALL path constants (Law: no hardcoded paths elsewhere)
│   ├── business/
│   │   ├── firefly/                   # Firefly III + Pico (containerized)
│   │   ├── paperless/                 # Paperless-NGX (containerized)
│   │   └── ...
│   ├── lib/
│   │   ├── mkContainer.nix            # Primary container helper (new domain pattern)
│   │   └── mkInfraContainer.nix       # Infrastructure container helper
│   └── ...
```

### Import Chain (how server services get loaded)

```
flake.nix
  └─ nixosConfigurations.hwc-server = nixpkgs-stable.lib.nixosSystem {
       modules = [
         agenix-stable.nixosModules.default
         home-manager-stable.nixosModules.home-manager
         ./machines/server/config.nix          ← machine entry point
       ];
     }

machines/server/config.nix
  imports = [
    ./hardware.nix
    ../../profiles/core.nix            ← system + secrets + data domains
    ../../domains/ai/index.nix
    ../../domains/networking/index.nix ← Caddy, routes, gluetun, podman-network
    ../../domains/data/index.nix
    ../../domains/media/index.nix
    ../../profiles/monitoring.nix
    ../../domains/business/index.nix
    ../../domains/notifications/index.nix
    ../../domains/gaming/index.nix
  ]
  # Plus: inline hwc.* option assignments enabling every service

profiles/core.nix
  imports = [
    ../domains/system/index.nix
    ../domains/secrets/index.nix
    ../domains/data/index.nix
  ]

domains/networking/index.nix
  imports = [
    ./reverseProxy.nix      # Caddy renderer + hwc.networking.shared.routes option
    ./routes.nix            # Pushes all service routes into hwc.networking.shared.routes
    ./podman-network.nix    # Creates media-network systemd oneshot
    ./gluetun/index.nix
    ./pihole/index.nix
    ./vpn/index.nix
    ./cloudflared/index.nix
  ]

profiles/server.nix (legacy, still imported)
  imports = [
    ../domains/infrastructure/index.nix
    ../domains/server/index.nix        ← containers + native aggregator
    ../domains/server/native/couchdb/index.nix
  ]

domains/server/index.nix
  imports = [
    ./options.nix
    ./containers/index.nix   ← imports all container modules
    ./native/index.nix       ← auto-discovers all native service modules
  ]

domains/server/containers/index.nix
  imports = [
    ./_shared/network.nix     ← init-media-network systemd service
    ./_shared/caddy.nix       ← legacy caddy renderer (old namespace)
    ./_shared/directories.nix ← shared tmpfiles rules
    ./gluetun/index.nix
    ./immich/index.nix
    ./sonarr/index.nix        (and all other containers)
    ...
  ]
```

### Namespace Convention

Container option paths follow the folder hierarchy:

```
domains/server/containers/sonarr/  →  hwc.server.containers.sonarr.*
domains/server/native/jellyfin/    →  hwc.server.native.jellyfin.*
domains/business/firefly/          →  hwc.business.firefly.*
domains/networking/gluetun/        →  hwc.networking.gluetun.*
```

---

## 2. Container Definition Patterns

### Pattern A: `_shared/pure.nix` helper (server containers namespace)

Used by: sonarr, radarr, lidarr, prowlarr, readarr, slskd, soularr, pinchflat, calibre, jellyseerr

Source file: `/home/eric/.nixos/domains/server/containers/_shared/pure.nix`

```nix
{ lib, pkgs }:
rec {
  mkContainer =
    { name
    , image
    , networkMode ? "media"      # "media" | "vpn"
    , gpuEnable ? true
    , gpuMode ? "intel"          # "intel" only in this helper
    , timeZone ? "UTC"
    , ports ? []
    , volumes ? []
    , environment ? {}
    , extraOptions ? []
    , dependsOn ? []
    , user ? null
    , cmd ? []
    }:
    let
      podmanNetworkOpts =
        if networkMode == "vpn"
        then [ "--network=container:gluetun" ]
        else [ "--network=media-network" ];
      gpuOpts = if (!gpuEnable) then [] else [ "--device=/dev/dri:/dev/dri" ];
      baseEnv = { PUID = "1000"; PGID = "100"; TZ = timeZone; };
    in {
      virtualisation.oci-containers.containers.${name} = {
        inherit image dependsOn;
        autoStart = true;
        environment = baseEnv // environment;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ extraOptions
          ++ [ "--memory=2g" "--cpus=1.0" "--memory-swap=4g" ];
        ports = ports;
        volumes = volumes;
      };
    };
}
```

**Key behaviors:**
- Always sets `PUID=1000`, `PGID=100` (users group, NOT 1000)
- Default resource limits: 2g RAM, 1 CPU, 4g swap
- Network defaults to `media-network` (bridge); VPN mode joins gluetun's network namespace

### Pattern B: `domains/lib/mkContainer.nix` (newer business/media domain pattern)

Used by: firefly, paperless, and new containers in non-server domains

Source file: `/home/eric/.nixos/domains/lib/mkContainer.nix`

```nix
{ lib, pkgs }:
rec {
  mkContainer =
    { name
    , image
    , networkMode ? "media"      # "media" | "vpn" | "host"
    , gpuEnable ? true
    , gpuMode ? "intel"          # "intel" | "nvidia-cdi" | "nvidia-legacy"
    , timeZone ? "UTC"
    , ports ? []
    , volumes ? []
    , environment ? {}
    , extraOptions ? []
    , dependsOn ? []
    , user ? null
    , cmd ? []
    , environmentFiles ? []
    , memory ? "2g"
    , cpus ? "1.0"
    , memorySwap ? "4g"
    , pull ? "missing"
    }:
    let
      podmanNetworkOpts =
        if networkMode == "vpn" then [ "--network=container:gluetun" ]
        else if networkMode == "host" then [ "--network=host" ]
        else [ "--network=media-network" ];
      gpuOpts =
        if (!gpuEnable) then []
        else if gpuMode == "nvidia-cdi" then [ "--device=nvidia.com/gpu=0" ]
        else if gpuMode == "nvidia-legacy" then [
          "--device=/dev/nvidia0:/dev/nvidia0:rwm"
          "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
          ...
        ]
        else [ "--device=/dev/dri:/dev/dri" ];
      baseEnv = { PUID = "1000"; PGID = "100"; TZ = timeZone; };
    in {
      virtualisation.oci-containers.containers.${name} = {
        inherit image dependsOn pull;
        autoStart = true;
        environment = baseEnv // environment;
        environmentFiles = environmentFiles;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ resourceOpts ++ extraOptions;
        ports = ports;
        volumes = volumes;
      };
    };
}
```

**Additions over pure.nix:**
- `environmentFiles` parameter (list of env files injected into container)
- `host` network mode
- Nvidia CDI and legacy GPU modes
- Configurable `memory`, `cpus`, `memorySwap`, `pull`

### Example 1: Sonarr (simple *arr container)

Source: `/home/eric/.nixos/domains/server/containers/sonarr/sys.nix`

```nix
# options.nix declares: hwc.server.containers.sonarr.{enable, image, network.mode, gpu.enable}
# image default: "lscr.io/linuxserver/sonarr:latest"

config = lib.mkIf cfg.enable (lib.mkMerge [
  (helpers.mkContainer {
    name = "sonarr";
    image = cfg.image;
    networkMode = cfg.network.mode;   # "media" default
    gpuEnable = cfg.gpu.enable;
    gpuMode = "intel";
    timeZone = config.time.timeZone or "UTC";
    ports = [ "127.0.0.1:8989:8989" ];
    volumes = [
      "${configPath}:/config"                          # /opt/sonarr/config
      "${config.hwc.paths.media.root}/tv:/tv"          # /mnt/media/tv
      "${config.hwc.paths.hot.root}/downloads:/downloads"  # /mnt/hot/downloads
    ];
    environment = {
      SONARR__URLBASE = "/sonarr";
    };
    dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
  })
]);
```

Enabling: In `machines/server/config.nix`:
```nix
hwc.media.sonarr.enable = lib.mkDefault true;
# or in the old namespace:
hwc.server.containers.sonarr.enable = lib.mkDefault true;
```

### Example 2: Immich (multi-container with GPU, Redis, database)

Source: `/home/eric/.nixos/domains/server/containers/immich/parts/config.nix` (truncated)

```nix
# Three containers: immich-server, immich-machine-learning, immich-redis
# All share media-network; DB is PostgreSQL on host (10.89.0.1 from container perspective)

virtualisation.oci-containers.containers.immich-server = {
  image = cfg.images.server;   # "ghcr.io/immich-app/immich-server:release"
  autoStart = true;
  dependsOn = lib.optionals cfg.redis.enable [ "immich-redis" ];
  extraOptions = networkOpts ++ [
    "--network-alias=immich-server"
    "--memory=2g" "--cpus=2.0" "--memory-swap=4g"
  ] ++ lib.optionals cfg.gpu.enable [ "--device=nvidia.com/gpu=0" ];
  ports = [ "127.0.0.1:2283:3001" ];
  environment = {
    DB_URL = "postgresql://eric@10.89.0.1:5432/immich";
    REDIS_HOSTNAME = "immich-redis";
    UPLOAD_LOCATION = "/mnt/media/photos/immich";
    NVIDIA_VISIBLE_DEVICES = "0";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
  };
  volumes = [ "${cfg.storage.basePath}:/usr/src/app/upload:rw" ... ];
};

# Systemd dependencies:
systemd.services."podman-immich-server" = {
  after = [ "network-online.target" "postgresql.service"
            "podman-immich-redis.service"
            "init-media-network.service"
            "nvidia-container-toolkit-cdi-generator.service" ];
  requires = [ "nvidia-container-toolkit-cdi-generator.service" ];
};
```

Enabling:
```nix
# machines/server/config.nix
hwc.media.immich = {
  enable = lib.mkDefault true;
  settings.port = 2283;
  storage.basePath = "/mnt/media/photos/immich";
  database.host = "127.0.0.1";
  redis.enable = true;
  gpu.enable = true;
  machineLearning.enable = true;
};
```

### Example 3: Gluetun (VPN gateway, special capabilities)

Source: `/home/eric/.nixos/domains/server/containers/gluetun/parts/config.nix`

```nix
# Secrets injected via a systemd oneshot that writes a .env file from agenix
systemd.services.gluetun-env-setup = {
  description = "Generate Gluetun env from agenix secrets";
  before   = [ "podman-gluetun.service" ];
  wantedBy = [ "podman-gluetun.service" ];
  wants    = [ "agenix.service" ];
  after    = [ "agenix.service" ];
  serviceConfig.Type = "oneshot";
  script = ''
    mkdir -p ${cfgRoot}
    WG_PRIVATE_KEY=$(cat ${config.age.secrets.vpn-wireguard-private-key.path})
    cat > ${cfgRoot}/.env <<EOF
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=$WG_PRIVATE_KEY
...
EOF
    chmod 600 ${cfgRoot}/.env
  '';
};

virtualisation.oci-containers.containers.gluetun = {
  image = cfg.image;     # "qmcgaw/gluetun:latest"
  autoStart = true;
  extraOptions = [
    "--cap-add=NET_ADMIN"
    "--cap-add=SYS_MODULE"
    "--device=/dev/net/tun:/dev/net/tun"
    "--network=media-network"
    "--network-alias=gluetun"
    "--privileged"
  ];
  ports = [
    "127.0.0.1:8080:8080"  # qBittorrent UI
    "127.0.0.1:8081:8085"  # SABnzbd
  ];
  volumes = [ "${cfgRoot}:/gluetun" ];
  environmentFiles = [ "${cfgRoot}/.env" ];
  environment = {
    TZ = "America/Denver";
    DOT = "off";
    DNS_ADDRESS = "1.1.1.1";
  };
};

systemd.services."podman-gluetun".after = [
  "network-online.target"
  "init-media-network.service"
];
```

### Example 4: Firefly III (business domain, uses newer mkContainer)

Source: `/home/eric/.nixos/domains/business/firefly/parts/config.nix`

```nix
# Uses domains/lib/mkContainer.nix helper
# Secrets via preStart script writing APP_KEY to env file
systemd.services."podman-firefly".preStart = lib.mkAfter ''
  APP_KEY=$(cat ${appKeyFile})
  echo "APP_KEY=base64:$APP_KEY" > ${fireflyEnvFile}
  chmod 644 ${fireflyEnvFile}
'';

# Container uses environmentFiles instead of environment for secrets:
mkContainer {
  name = "firefly";
  image = "docker.io/fireflyiii/core:latest";
  networkMode = "media";
  gpuEnable = false;
  memory = "1g";
  cpus = "1.0";
  environmentFiles = [ "${fireflyRoot}/.env" ];
  ports = [ "127.0.0.1:8085:8080" ];
  volumes = [ "${fireflyUpload}:/var/www/html/storage/upload:rw" ];
  environment = {
    APP_URL = "https://hwc-server.ocelot-wahoo.ts.net:10443";
    DB_CONNECTION = "pgsql";
    DB_HOST = "10.89.0.1";   # media-network gateway — NEVER "localhost" from containers
    DB_PORT = "5432";
    DB_DATABASE = "firefly";
    DB_USERNAME = "eric";
  };
}
```

### Container Module File Structure

Every container module follows this layout:

```
domains/server/containers/<name>/
├── index.nix      # Aggregator: imports options + sys/parts, mkIf wrapper
├── options.nix    # Option declarations (hwc.server.containers.<name>.*)
├── sys.nix        # Container definition (uses pure.nix helper)
└── parts/         # Optional: for complex containers
    ├── config.nix # App-specific config generation (templates, env files)
    ├── scripts.nix
    ├── pkgs.nix
    └── lib.nix
```

Minimal `index.nix`:
```nix
{ lib, config, pkgs, ... }:
let cfg = config.hwc.server.containers.<name>;
in {
  imports = [ ./options.nix ./sys.nix ];
  config = lib.mkIf cfg.enable { };
}
```

Minimal `options.nix`:
```nix
{ lib, ... }:
let inherit (lib) mkOption mkEnableOption types;
in {
  options.hwc.server.containers.<name> = {
    enable = mkEnableOption "<name> container";
    image  = mkOption { type = types.str; default = "lscr.io/linuxserver/<name>:latest"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable   = mkOption { type = types.bool; default = false; };
  };
}
```

---

## 3. Port Allocation — Full Map

Source: `/home/eric/.nixos/domains/networking/routes.nix`

All external ports use Tailscale TLS (Caddy + `get_certificate tailscale`).
Domain: `hwc-server.ocelot-wahoo.ts.net`

### Dedicated Port Mode (HTTPS on separate port)

| External Port | Service          | Internal Port/Upstream          | Notes |
|---------------|------------------|---------------------------------|-------|
| 1443          | calibre          | http://127.0.0.1:8083           | Desktop KasmVNC |
| 2443          | n8n              | http://127.0.0.1:5678           | Workflow automation |
| 2586          | gotify           | http://127.0.0.1:2587           | Push notifications |
| 3443          | yt-transcripts-api | http://127.0.0.1:8100         | YouTube transcript API |
| 4443          | grafana          | http://127.0.0.1:3000           | Monitoring dashboards |
| 5043          | mousehole        | http://127.0.0.1:5010           | MAM seedbox IP updater |
| 5443          | frigate          | http://127.0.0.1:5000           | NVR (GPU/CUDA) |
| 5543          | jellyseerr       | http://127.0.0.1:5055           | Media requests |
| 6443          | jellyfin         | http://127.0.0.1:8096           | Media server |
| 7443          | immich           | http://127.0.0.1:2283           | Photo management |
| 8267          | tdarr            | http://127.0.0.1:8265           | Video transcoding |
| 8443          | slskd            | http://127.0.0.1:5031           | Soulseek client |
| 8943          | pinchflat        | http://127.0.0.1:8945           | YouTube subscriptions |
| 9443          | organizr         | http://127.0.0.1:9983           | Dashboard |
| 10443         | firefly          | http://127.0.0.1:8085           | Personal finance |
| 11443         | firefly-pico     | http://127.0.0.1:8086           | Finance mobile companion |
| 12443         | cloudbeaver      | http://127.0.0.1:8978           | DB manager |
| 13443         | estimator        | (static React app)              | Heartwood estimator |
| 14443         | calculator       | static: `.../calculator/app/dist` | Static React app |
| 15443         | vaultwarden      | http://127.0.0.1:<vaultwarden.port> | Password manager |
| 16443         | briefing         | static: `.../morning-briefing/dashboard` | Daily briefing |
| 18095         | heartwood-cms    | http://127.0.0.1:8095           | CMS dashboard |

### Subpath Mode (routed under main domain HTTPS)

| Path           | Service          | Internal Port | needsUrlBase |
|----------------|------------------|---------------|--------------|
| /sonarr        | sonarr           | 8989          | true         |
| /radarr        | radarr           | 7878          | true         |
| /lidarr        | lidarr           | 8686          | true         |
| /readarr       | readarr          | 8787          | true         |
| /prowlarr      | prowlarr         | 9696          | true         |
| /music         | navidrome        | 4533          | true         |
| /sab           | sabnzbd          | 8081          | true         |
| /qbt           | qbittorrent      | 8080          | false        |
| /books         | lazylibrarian    | 5299          | true         |
| /audiobookshelf| audiobookshelf   | 13378         | true         |
| /calibre       | calibre content  | 8090          | false        |
| /sync          | couchdb          | 5984          | false        |
| /docs          | paperless-ngx    | 8102          | true         |
| /webhook       | n8n webhooks     | 5678          | true         |
| /jellyseerr    | jellyseerr (alt) | 5055          | false        |
| /media         | jellyfin (alt)   | 8096          | true         |
| /retroarch-sync| webdav           | (native)      | true         |

### Internal-Only Ports (not exposed via Caddy)

| Port  | Service                      |
|-------|------------------------------|
| 5432  | PostgreSQL                   |
| 6379  | Redis                        |
| 6380  | Immich Redis                 |
| 5984  | CouchDB (Tailscale + /sync)  |
| 9100  | Prometheus node-exporter     |
| 9090  | Prometheus                   |
| 9093  | Alertmanager                 |
| 9095  | Alertmanager→gotify bridge   |
| 9115  | Blackbox exporter            |
| 11434 | Ollama                       |

### Reserved Ranges

- `14000–14099` — `hwc-publish` web app slots (on tailscale0)
- `1443–18095` — Named services (port mode)
- All container internal ports: bound to `127.0.0.1` only

---

## 4. Caddy / Reverse Proxy

### Configuration Entry Point

Source: `/home/eric/.nixos/domains/networking/reverseProxy.nix`

The Caddy config is **fully generated** from the `hwc.networking.shared.routes` list. No manual Caddy config exists. All routes are declared in `routes.nix` and rendered by `reverseProxy.nix`.

### Option Declarations

```nix
options.hwc.networking.reverseProxy = {
  enable = mkEnableOption "Reverse proxy service (Caddy)";
  domain = mkOption { type = types.str; default = "hwc-server.ocelot-wahoo.ts.net"; };
};

options.hwc.networking.shared = {
  tailscaleDomain = mkOption { type = types.str; default = "hwc-server.ocelot-wahoo.ts.net"; };
  rootHost        = mkOption { type = types.str; default = "hwc-server.ocelot-wahoo.ts.net"; };
  routes = mkOption {
    type = types.listOf (types.attrsOf types.anything);
    default = [];
  };
};
```

### Route Schema

Each route is an attrset with these keys:

| Key          | Required | Values                    | Description |
|--------------|----------|---------------------------|-------------|
| `name`       | yes      | string                    | Unique identifier |
| `mode`       | yes      | `"port"` `"subpath"` `"static"` | Routing mode |
| `port`       | port mode | int                      | External TLS port |
| `upstream`   | port/subpath | `"http://127.0.0.1:N"` | Internal upstream |
| `path`       | subpath  | `"/prefix"`               | URL prefix to match |
| `needsUrlBase` | subpath | bool                    | Preserve path (true) or strip it (false) |
| `root`       | static   | absolute path             | Static file directory |
| `headers`    | no       | attrset                   | Extra header_up directives |
| `ws`         | no       | bool (default true)       | Enable WebSocket flush |

### Generated Caddy Config Structure

```
# Loopback subpath routes (bind 127.0.0.1)
localhost {
  bind 127.0.0.1
  tls internal
  encode zstd gzip
  <all subpath routes>
}

# Tailscale serve backend (plain HTTP, tailscaled terminates TLS)
:18080 {
  encode zstd gzip
  @mcp_routes { path /mcp /mcp/* /health /.well-known/* }
  handle @mcp_routes { reverse_proxy 127.0.0.1:6200 { ... } }
  <all subpath routes>
}

# Dedicated TLS port per service (port mode)
hwc-server.ocelot-wahoo.ts.net:6443 {
  tls { get_certificate tailscale; protocols tls1.2 tls1.3; alpn h2 http/1.1 }
  encode zstd gzip
  reverse_proxy http://127.0.0.1:8096 {
    header_up Host {host}
    header_up X-Real-IP {remote}
    header_up X-Forwarded-For {remote}
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-Host {host}
    flush_interval -1
  }
}

# Static file servers (static mode)
hwc-server.ocelot-wahoo.ts.net:14443 {
  tls { get_certificate tailscale; ... }
  encode zstd gzip
  header Access-Control-Allow-Origin "*"
  root * /path/to/dist
  try_files {path} /index.html
  file_server
}

# Public MCP funnel port (Tailscale Funnel terminates TLS on :10000)
:10080 { ... }
```

### Caddy systemd overrides

```nix
systemd.services.caddy = {
  serviceConfig = {
    User  = lib.mkForce "root";
    Group = lib.mkForce "root";
    PrivateUsers  = lib.mkForce false;
    ProtectHome   = lib.mkForce false;
  };
};
```

### Adding a Route

Add to the list in `domains/networking/routes.nix`:

```nix
# Port mode example:
{
  name = "myapp";
  mode = "port";
  port = 9999;                          # must be unused — check the full port map above
  upstream = "http://127.0.0.1:8199";
}

# Subpath mode, app has URL base:
{
  name = "myapp";
  mode = "subpath";
  path = "/myapp";
  upstream = "http://127.0.0.1:8199";
  needsUrlBase = true;
  headers = { "X-Forwarded-Prefix" = "/myapp"; };
}
```

---

## 5. Secrets Management

### Tool: agenix

Secrets are encrypted `.age` files decrypted at activation time by the `agenix` NixOS module. Decrypted secrets land at `/run/agenix/<name>` (a tmpfs, cleared on reboot).

### File Locations

```
secrets.nix                                  # Recipient rules (which pubkeys decrypt each secret)
domains/secrets/
├── index.nix                                # Master aggregator
├── declarations/
│   ├── index.nix                            # Imports all declaration files
│   ├── infrastructure.nix                   # VPN, cameras, cloudflare creds
│   ├── services.nix                         # App API keys, passwords
│   ├── server.nix                           # Server-specific service creds
│   ├── system.nix
│   ├── home.nix
│   └── caddy.nix
└── parts/
    ├── infrastructure/                      # *.age encrypted files
    ├── services/                            # *.age encrypted files
    └── ...
```

### Declaring a Secret

**Step 1: Add to `secrets.nix`** (recipient rules):

```nix
# secrets.nix
"domains/secrets/parts/services/myservice-api-key.age".publicKeys = everyone;
```

**Step 2: Encrypt the secret:**

```bash
cd /home/eric/.nixos
agenix -e domains/secrets/parts/services/myservice-api-key.age
```

**Step 3: Declare in the appropriate declarations file** (e.g., `domains/secrets/declarations/services.nix`):

```nix
age.secrets.myservice-api-key = {
  file = ../parts/services/myservice-api-key.age;
  mode = "0440";          # ALWAYS 0440
  owner = "root";         # Usually root
  group = "secrets";      # ALWAYS "secrets"
};
```

### Accessing Secrets in Container Configs

**Direct path reference** (for systemd scripts):
```nix
config.age.secrets.myservice-api-key.path
# → "/run/agenix/myservice-api-key"
```

**Via hwc.secrets.api** (auto-populated map):
```nix
config.hwc.secrets.api."myservice-api-key"
# Equivalent to config.age.secrets.myservice-api-key.path
```

**Pattern 1: environmentFiles (preferred for containers)**

Write secret to a temp env file via a systemd oneshot before the container starts:

```nix
systemd.services.myservice-env-setup = {
  description = "Generate myservice env from agenix secrets";
  before   = [ "podman-myservice.service" ];
  wantedBy = [ "podman-myservice.service" ];
  wants    = [ "agenix.service" ];
  after    = [ "agenix.service" ];
  serviceConfig.Type = "oneshot";
  script = ''
    mkdir -p /opt/myservice
    API_KEY=$(cat ${config.age.secrets.myservice-api-key.path})
    cat > /opt/myservice/.env <<EOF
MY_API_KEY=$API_KEY
EOF
    chmod 600 /opt/myservice/.env
  '';
};

virtualisation.oci-containers.containers.myservice = {
  environmentFiles = [ "/opt/myservice/.env" ];
  ...
};
```

**Pattern 2: systemd preStart (used by firefly, navidrome)**

```nix
systemd.services."podman-myservice".preStart = lib.mkAfter ''
  SECRET=$(cat ${config.age.secrets.myservice-secret.path})
  echo "MY_SECRET=$SECRET" > /opt/myservice/.env
  chmod 644 /opt/myservice/.env
'';
```

**Pattern 3: Native service via LoadCredential (used by navidrome)**

```nix
systemd.services.navidrome = {
  serviceConfig.LoadCredential = "navidrome-password:${cfg.settings.initialAdminPasswordFile}";
  environment.ND_INITIAL_ADMIN_PASSWORD = "%d/navidrome-password";
};
```

### Secret Group Membership

The `secrets` group (GID varies) must include any service user that reads `/run/agenix/*` files with `mode = "0440"`. The user `eric` is automatically in the `secrets` group. Root always has access.

---

## 6. Systemd Service Patterns

### Native NixOS Services (non-container)

Pattern: run as `eric:users` with `lib.mkForce` to override module defaults.

Source: `/home/eric/.nixos/domains/server/native/navidrome/index.nix`

```nix
services.navidrome = {
  enable = true;
  settings = { Address = "0.0.0.0"; Port = 4533; MusicFolder = "/mnt/media/music"; };
};

systemd.services.navidrome = {
  serviceConfig = {
    User  = lib.mkForce "eric";      # CRITICAL: lib.mkForce required
    Group = lib.mkForce "users";
    StateDirectory = lib.mkForce "hwc/navidrome";
    WorkingDirectory = lib.mkForce "/var/lib/hwc/navidrome";
    LoadCredential = "navidrome-password:${passwordFile}";
  };
  environment.ND_INITIAL_ADMIN_PASSWORD = "%d/navidrome-password";
};
```

**Rule: `lib.mkForce` is mandatory** for User/Group on native services. Without it the module's default wins.

### Container Systemd Services

`virtualisation.oci-containers.containers.<name>` creates a systemd service named `podman-<name>`.

To add dependencies:

```nix
systemd.services."podman-myservice" = {
  after = [
    "network-online.target"
    "init-media-network.service"   # if using media-network
    "postgresql.service"           # if needing DB
    "agenix.service"               # if reading secrets in preStart
    "podman-otherdep.service"      # if depending on another container
  ];
  requires = [ "init-media-network.service" ];
  wants = [ "network-online.target" ];

  serviceConfig.ExecStartPre = [
    "+${someScript}"               # + prefix = run as root
  ];
};
```

### Shared Directory Setup

Source: `/home/eric/.nixos/domains/server/containers/_shared/directories.nix`

The shared `_shared/directories.nix` creates all standard container config directories at `/opt/<name>/config` (owned `1000:100`) during system activation via `systemd.tmpfiles.rules`. Individual containers can add additional rules in their own `sys.nix`.

Pattern for additional dirs:

```nix
systemd.tmpfiles.rules = [
  "d /opt/myservice         0755 1000 100 -"   # app root
  "d /opt/myservice/config  0755 1000 100 -"   # config dir
  "d /opt/myservice/data    0755 1000 100 -"   # data dir
];
```

`tmpfiles` format: `"<type> <path> <mode> <user> <group> <age>"`

### init-media-network Service

Source: `/home/eric/.nixos/domains/networking/podman-network.nix`

```nix
systemd.services.init-media-network = {
  description = "Create podman media network (idempotent)";
  after  = [ "network-online.target" ];
  wants  = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  script = ''
    if ! podman network ls --format "{{.Name}}" | grep -qx media-network; then
      podman network create media-network
    fi
  '';
};
```

Any container on `media-network` must declare:
```nix
systemd.services."podman-<name>".after = [ "init-media-network.service" ];
```

---

## 7. Domain / DNS Structure

### Access Domains

| Domain | Type | Used for |
|--------|------|----------|
| `hwc-server.ocelot-wahoo.ts.net` | Tailscale HTTPS | All services (port + subpath mode) |
| `webhooks.heartwoodcraft.me` | Cloudflare tunnel | External webhook ingress → n8n |
| `heartwoodcraft.me` | Hostinger hosting | Public business site |

### TLS Configuration

All TLS is handled by Caddy using Tailscale certificate provisioning:

```
tls {
  get_certificate tailscale
  protocols tls1.2 tls1.3
  alpn h2 http/1.1
}
```

The `services.tailscale.permitCertUid = "caddy"` in machine config gives Caddy permission to fetch Tailscale certs.

### Tailscale Network Architecture

- Tailscale domain: `hwc-server.ocelot-wahoo.ts.net`
- CGNAT range: `100.64.0.0/10` (used for trusted proxies in apps like Immich)
- Services listen on `127.0.0.1:<port>` — Caddy proxies from Tailscale IP

---

## 8. Rebuild Process

### Commands

```bash
# Standard rebuild (from /home/eric/.nixos)
hostname   # MUST confirm hostname first (hooks enforce this)
sudo nixos-rebuild switch --flake .#hwc-server

# Dry run / syntax check only
sudo nixos-rebuild dry-build --flake .#hwc-server

# NixOS check
nix flake check

# Skills available:
/build   # dry-build
/check   # nix flake check
/cp      # commit + push
/status  # git status
```

### Important: Track New Files Before Rebuild

```bash
git add domains/server/containers/mynewservice/
# Nix flakes only see git-tracked files. Untracked files are invisible to the build.
```

### Rebuild Sequence for New Container

1. `git add` all new files
2. `nix flake check` — catches Nix syntax errors
3. `sudo nixos-rebuild dry-build --flake .#hwc-server` — full eval, no activation
4. `sudo nixos-rebuild switch --flake .#hwc-server` — activate

---

## 9. Networking — Tailscale, Gluetun, Firewall

### Tailscale

Configured in `machines/server/config.nix`:

```nix
hwc.system.networking = {
  tailscale.enable = true;
  tailscale.funnel.enable = false;  # n8n uses its own funnel on port 10000
  tailscale.extraUpFlags = [ "--advertise-tags=tag:server" "--accept-routes" ];
};
```

- Tailscale interface: `tailscale0`
- Tailscale HTTPS certs: provisioned by Caddy via `get_certificate tailscale`
- Funnel (public internet exposure): disabled globally, n8n has dedicated `:10000` funnel

### Gluetun VPN

Gluetun runs as a container on `media-network`. Containers that need VPN join its network namespace:

```nix
extraOptions = [ "--network=container:gluetun" ];
```

**VPN containers** (running through gluetun): `qbittorrent`, `sabnzbd`, and optionally any *arr container.

Current gluetun config (from `parts/config.nix`):
- Provider: ProtonVPN via WireGuard (custom)
- Endpoint: `74.63.204.210:51820` (US-UT#52)
- Private key: from agenix secret `vpn-wireguard-private-key`

Gluetun exposes two ports for services inside the VPN namespace:
- `:8080` → qBittorrent web UI
- `:8081` → SABnzbd (internal port 8085)

### Firewall

Firewall level is `"server"` (strict). All additional ports must be explicitly opened.

**Mechanism 1: `networking.firewall.allowedTCPPorts`** (global, opens on all interfaces)

**Mechanism 2: `networking.firewall.interfaces."tailscale0".allowedTCPPorts`** (Tailscale-only, more secure)

Caddy auto-opens port 80, 443, and all `mode = "port"` / `mode = "static"` route ports via:
```nix
networking.firewall.allowedTCPPorts =
  [ 80 443 ]
  ++ (lib.map (r: r.port) (lib.filter (r: r.mode == "port" || r.mode == "static") routes));
```

**Currently open TCP ports** (from `machines/server/config.nix`):
```
22000   # Syncthing sync
5000    # Frigate
8080    # qBittorrent
7878    # Radarr
8989    # Sonarr
8686    # Lidarr
8787    # Readarr
9696    # Prowlarr
5055    # Jellyseerr
4533    # Navidrome
8096    # Jellyfin
2283    # Immich
8081    # SABnzbd
5030    # SLSKD
8888    # Receipt API
8501    # Streamlit
5432    # PostgreSQL
6379    # Redis
3000    # Grafana
9090    # Prometheus
9093    # Alertmanager
11434   # Ollama
5909    # Calibre VNC
8943    # Pinchflat
47984 47989 47990 48010  # Sunshine game streaming
7359    # Jellyfin discovery
```

### Cloudflare Tunnel

Source: `domains/networking/cloudflared/index.nix`

Exposes `webhooks.heartwoodcraft.me` → n8n for external webhook ingress (Quo, etc.).

```nix
hwc.networking.cloudflared = {
  enable = true;
  tunnelId = "1536327b-2641-4706-8ad9-48c94d0b11f9";
  credentialsFile = config.age.secrets.cloudflared-tunnel-credentials.path;
};
```

### Podman Network

Name: `media-network`
Gateway: `10.89.0.1` (used by containers to reach host services like PostgreSQL and Redis)

**Critical**: Containers CANNOT use `localhost` or `127.0.0.1` to reach host services. They must use `10.89.0.1`.

---

## 10. Existing Services Inventory

| Service | Type | Namespace | Internal Port | External | VPN | GPU | Secrets |
|---------|------|-----------|---------------|----------|-----|-----|---------|
| Gluetun | container | `hwc.networking.gluetun` | — | — | IS VPN | no | `vpn-wireguard-private-key` |
| qBittorrent | container | `hwc.media.qbittorrent` | 8080 | /qbt | yes | yes | — |
| SABnzbd | container | `hwc.media.sabnzbd` | 8081 | /sab | yes | yes | — |
| Prowlarr | container | `hwc.media.prowlarr` | 9696 | /prowlarr | no | yes | `prowlarr-api-key` |
| Sonarr | container | `hwc.media.sonarr` | 8989 | /sonarr | no | yes | `sonarr-api-key` |
| Radarr | container | `hwc.media.radarr` | 7878 | /radarr | no | yes | `radarr-api-key` |
| Lidarr | container | `hwc.media.lidarr` | 8686 | /lidarr | no | yes | `lidarr-api-key` |
| Readarr | container | `hwc.media.readarr` | 8787 | /readarr | no | yes | — |
| LazyLibrarian | container | `hwc.media.books` | 5299 | /books | no | yes | — |
| Calibre | container | `hwc.media.calibre` | 8083, 8090 | :1443, /calibre | no | yes | — |
| Audiobookshelf | container | `hwc.media.audiobookshelf` | 13378 | /audiobookshelf | no | no | `audiobookshelf-api-key` |
| Jellyseerr | container | `hwc.media.jellyseerr` | 5055 | :5543, /jellyseerr | no | yes | — |
| Immich (server) | container | `hwc.media.immich` | 2283 | :7443 | no | yes (nvidia) | `immich-api-key` |
| Immich (ML) | container | `hwc.media.immich` | — | — | no | yes (nvidia) | — |
| Immich (Redis) | container | `hwc.media.immich` | 6379 | — | no | no | — |
| Pinchflat | container | `hwc.media.pinchflat` | 8945 | :8943 | no | no | — |
| SLSKD | container | `hwc.media.slskd` | 5031 | :8443 | no | no | `slskd-*` |
| Soularr | container | `hwc.media.soularr` | — | — | no | no | `lidarr-api-key` |
| Recyclarr | container | `hwc.media.recyclarr` | — | — | no | no | `*-api-key` |
| Mousehole | container | `hwc.media.mousehole` | 5010 | :5043 | no | no | — |
| Organizr | container | `hwc.server.containers.organizr` | 9983 | :9443 | no | no | — |
| Tdarr | container | `hwc.media.tdarr` | 8265 | :8267 | no | no | — |
| Jellyfin | native | `hwc.media.jellyfin` | 8096 | :6443, /media | no | yes (nvidia) | `jellyfin-api-key` |
| Navidrome | native | `hwc.media.navidrome` | 4533 | /music | no | no | `navidrome-admin-password` |
| Frigate NVR | native+container | `hwc.media.frigate` | 5001 | :5443 | no | yes (cuda) | `frigate-rtsp-*`, `frigate-camera-ips` |
| Immich (DB setup) | native | — | 5432 | — | no | no | — |
| CouchDB | native | `hwc.data.couchdb` | 5984 | /sync | no | no | `couchdb-admin-*` |
| PostgreSQL | native | `hwc.data.databases.postgresql` | 5432 | — | no | no | — |
| Redis | native | `hwc.data.databases.redis` | 6379 | — | no | no | — |
| Prometheus | native | `hwc.server.native.monitoring.prometheus` | 9090 | :4443/prometheus | no | no | — |
| Grafana | native | `hwc.server.native.monitoring.grafana` | 3000 | :4443 | no | no | `grafana-admin-password` |
| Alertmanager | native | `hwc.server.native.monitoring.alertmanager` | 9093 | — | no | no | — |
| Ollama | native | `hwc.ai.ollama` | 11434 | — | no | yes (nvidia) | — |
| n8n | native | `hwc.automation.n8n` | 5678 | :2443, /webhook | no | no | `n8n-*` |
| Firefly III | container | `hwc.business.firefly` | 8085 | :10443 | no | no | `firefly-app-key` |
| Firefly-Pico | container | `hwc.business.firefly` | 8086 | :11443 | no | no | — |
| Paperless-NGX | container | `hwc.business.paperless` | 8102 | /docs | no | no | `paperless-secret-key`, `paperless-admin-password` |
| Vaultwarden | container | `hwc.secrets.vaultwarden` | varies | :15443 | no | no | `vaultwarden-admin-token` |
| Gotify | container | `hwc.notifications.gotify` | 2587 | :2586 | no | no | `gotify-admin-password` |
| CloudBeaver | container | `hwc.data.cloudbeaver` | 8978 | :12443 | no | no | — |
| YT Transcripts API | native | `hwc.media.youtube.transcripts` | 8100 | :3443 | no | no | — |
| Heartwood CMS | native | `hwc.business.website` | 8095 | :18095 | no | no | `cms-api-key` |
| Estimator | native | `hwc.business.estimator` | 13443 | :13443 | no | no | `estimator-api-key` |
| CloudFlared | native | `hwc.networking.cloudflared` | — | (public) | no | no | `cloudflared-tunnel-credentials` |
| Pihole | container | `hwc.networking.pihole` | varies | — | no | no | — |
| Syncthing | native | `hwc.data.syncthing` | — | — | no | no | — |

---

## 11. Common Pitfalls

### 1. PGID Must Be 100 (Not 1000)

```nix
# WRONG — causes permission failures silently
PGID = "1000";

# CORRECT — users group is GID 100 on this system
PGID = "100";
```

The `mkContainer` helpers both set this correctly. Only fails when using `virtualisation.oci-containers.containers` directly without a helper.

### 2. Containers Cannot Use localhost for Host Services

```nix
# WRONG — containers cannot reach host services via localhost
database.host = "127.0.0.1";

# CORRECT — media-network gateway IP
database.host = "10.89.0.1";
```

This applies to: PostgreSQL (5432), Redis (6379), any native service.

### 3. New Files Must Be git-tracked Before Rebuild

```bash
# Nix flakes only evaluate git-tracked files
git add domains/server/containers/mynewservice/
# Then rebuild
```

### 4. `lib.mkForce` Required for Native Service User Override

```nix
# WRONG — module default wins
systemd.services.navidrome.serviceConfig.User = "eric";

# CORRECT
systemd.services.navidrome.serviceConfig.User = lib.mkForce "eric";
```

### 5. Port Conflicts

Always check the full port map (Section 3) before allocating a new port. Both internal (container) ports and external (Caddy) ports must be unique. Common conflicts: new service picks 8080 (qBittorrent), 8085 (SABnzbd internal), 8096 (Jellyfin).

### 6. osConfig Safety in Home Manager Modules

```nix
# WRONG — crashes when osConfig = {}
osConfig.hwc.x or null

# CORRECT
osConfig.hwc or {}
lib.attrByPath ["hwc" "x"] null osConfig
```

### 7. Assertions Must Be Inside `config = lib.mkIf ...`

```nix
# WRONG — assertions at top level cause infinite recursion
assertions = [ { assertion = cfg.enable; message = "..."; } ];

# CORRECT
config = lib.mkIf cfg.enable {
  assertions = [ { assertion = ...; message = "..."; } ];
};
```

### 8. Secret Mode and Group

```nix
# ALL secrets must use:
mode  = "0440";
group = "secrets";
# Never 0600, never group "root" (unless genuinely root-only like frigate-rtsp-username)
```

### 9. VPN Network Mode — Port Exposure Handled by Gluetun

When `network.mode = "vpn"`, the container shares gluetun's network namespace. The container must NOT declare `ports` — gluetun exposes them. Gluetun's `ports` list in `parts/config.nix` must include any service ports.

### 10. `lib.mkDefault` in Machine Config

Use `lib.mkDefault` when enabling services in `machines/server/config.nix` so profiles or other modules can override:

```nix
hwc.media.sonarr.enable = lib.mkDefault true;
```

---

## 12. Step-by-Step: Adding a New Container

This synthesizes everything above into a concrete checklist.

### Prerequisites

- Confirm hostname: `hostname` → must be `hwc-server`
- Determine: name, image, internal port, external access (port or subpath), secrets needed

### Step 1: Create the module directory

```bash
mkdir -p /home/eric/.nixos/domains/server/containers/<name>/parts
```

### Step 2: Write `options.nix`

```nix
# domains/server/containers/<name>/options.nix
{ lib, ... }:
let inherit (lib) mkOption mkEnableOption types;
in {
  options.hwc.server.containers.<name> = {
    enable = mkEnableOption "<name> container";
    image  = mkOption {
      type    = types.str;
      default = "lscr.io/linuxserver/<name>:latest";  # or ghcr.io/...
    };
    port = mkOption {
      type    = types.port;
      default = <INTERNAL_PORT>;
    };
    network.mode = mkOption {
      type    = types.enum [ "media" "vpn" ];
      default = "media";
    };
    gpu.enable = mkOption { type = types.bool; default = false; };
  };
}
```

### Step 3: Write `sys.nix` (container definition)

```nix
# domains/server/containers/<name>/sys.nix
{ lib, config, pkgs, ... }:
let
  helpers   = import ../_shared/pure.nix { inherit lib pkgs; };
  cfg       = config.hwc.server.containers.<name>;
  appsRoot  = config.hwc.paths.apps.root;    # /opt
  configPath = "${appsRoot}/<name>/config";
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name        = "<name>";
      image       = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable   = cfg.gpu.enable;
      timeZone    = config.time.timeZone or "UTC";
      ports       = [ "127.0.0.1:${toString cfg.port}:<INTERNAL_PORT>" ];
      volumes     = [
        "${configPath}:/config"
        # Add media mounts as needed:
        # "${config.hwc.paths.media.root}/tv:/tv"
        # "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        # APP-specific env vars (NOT secrets — those go via environmentFiles)
        # MYAPP__URLBASE = "/<name>";   # if using subpath routing
      };
      dependsOn = [];   # e.g., [ "prowlarr" ] or [ "gluetun" ]
    })

    # Directory setup
    {
      systemd.tmpfiles.rules = [
        "d ${configPath} 0755 1000 100 -"
      ];
    }

    # Systemd dependencies
    {
      systemd.services."podman-<name>" = {
        after = [ "network-online.target" "init-media-network.service" ];
        wants = [ "network-online.target" ];
      };
    }
  ]);
}
```

### Step 4: Write `index.nix`

```nix
# domains/server/containers/<name>/index.nix
{ lib, config, pkgs, ... }:
let cfg = config.hwc.server.containers.<name>;
in {
  imports = [ ./options.nix ./sys.nix ];
  config = lib.mkIf cfg.enable { };
}
```

### Step 5: Register in the container aggregator

Edit `/home/eric/.nixos/domains/server/containers/index.nix`, add to imports:

```nix
./<name>/index.nix
```

Also add to `_shared/directories.nix` in the `mkConfigDirs` list if using standard `/opt/<name>/config` layout:

```nix
mkConfigDirs [
  ...
  "<name>"   # ← add here
]
```

### Step 6: Add secrets (if needed)

**a) Encrypt the secret:**
```bash
cd /home/eric/.nixos
# Add to secrets.nix first:
#   "domains/secrets/parts/services/<name>-api-key.age".publicKeys = everyone;
agenix -e domains/secrets/parts/services/<name>-api-key.age
```

**b) Declare in `domains/secrets/declarations/services.nix`:**
```nix
age.secrets."<name>-api-key" = {
  file  = ../parts/services/<name>-api-key.age;
  mode  = "0440";
  owner = "root";
  group = "secrets";
};
```

**c) Use in `sys.nix` or `parts/config.nix`:**
```nix
# Inject via env file (recommended):
systemd.services."<name>-env-setup" = {
  before = [ "podman-<name>.service" ];
  wantedBy = [ "podman-<name>.service" ];
  wants = [ "agenix.service" ];
  after = [ "agenix.service" ];
  serviceConfig.Type = "oneshot";
  script = ''
    API_KEY=$(cat ${config.age.secrets.<name>-api-key.path})
    cat > /opt/<name>/.env <<EOF
MY_API_KEY=$API_KEY
EOF
    chmod 600 /opt/<name>/.env
  '';
};

# In mkContainer call:
environmentFiles = [ "/opt/<name>/.env" ];
```

### Step 7: Add the reverse proxy route

Edit `/home/eric/.nixos/domains/networking/routes.nix`, add to the list:

```nix
# Port mode (recommended for most apps):
{
  name     = "<name>";
  mode     = "port";
  port     = <NEW_EXTERNAL_PORT>;    # Must be unused — check Section 3
  upstream = "http://127.0.0.1:${toString cfg.port}";
}

# Subpath mode (if app supports URL base):
{
  name         = "<name>";
  mode         = "subpath";
  path         = "/<name>";
  upstream     = "http://127.0.0.1:${toString cfg.port}";
  needsUrlBase = true;
  headers      = { "X-Forwarded-Prefix" = "/<name>"; };
}
```

**Note:** For the route to reference `config`, it must be inside a module (not a plain list). Check how existing routes reference dynamic config values — the routes list in `routes.nix` is a NixOS module with `config` in scope.

### Step 8: Open firewall (if needed beyond Caddy)

If the service needs direct access outside of Caddy (e.g., P2P ports):

```nix
# In sys.nix:
networking.firewall.allowedTCPPorts = [ <PORT> ];
# Or, Tailscale-only:
networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ <PORT> ];
```

Caddy automatically opens the Caddy route port — no manual firewall rule needed for that.

### Step 9: Enable in machine config

Edit `/home/eric/.nixos/machines/server/config.nix`:

```nix
# Enable the new service:
hwc.server.containers.<name>.enable = lib.mkDefault true;

# If it needs firewall ports directly (not covered by Caddy):
hwc.system.networking.firewall.extraTcpPorts = [
  # existing ports...
  <NEW_PORT>
];
```

### Step 10: Track, check, rebuild

```bash
cd /home/eric/.nixos

# Stage all new/modified files
git add domains/server/containers/<name>/
git add domains/networking/routes.nix
git add domains/secrets/declarations/services.nix
git add domains/secrets/parts/services/<name>-api-key.age
git add machines/server/config.nix

# Syntax + eval check (no activation)
nix flake check
sudo nixos-rebuild dry-build --flake .#hwc-server

# Activate
sudo nixos-rebuild switch --flake .#hwc-server

# Verify
systemctl status podman-<name>
podman logs <name>
```

### Step 11: Verify the container is running

```bash
podman ps | grep <name>
curl -I https://hwc-server.ocelot-wahoo.ts.net:<PORT>/
journalctl -u podman-<name> -n 50
```

### Quick Reference: File Checklist

| File | Action |
|------|--------|
| `domains/server/containers/<name>/options.nix` | CREATE |
| `domains/server/containers/<name>/sys.nix` | CREATE |
| `domains/server/containers/<name>/index.nix` | CREATE |
| `domains/server/containers/index.nix` | EDIT — add import |
| `domains/server/containers/_shared/directories.nix` | EDIT — add to mkConfigDirs list |
| `domains/networking/routes.nix` | EDIT — add route entry |
| `domains/secrets/declarations/services.nix` | EDIT — add age.secrets declaration |
| `secrets.nix` | EDIT — add recipient rule |
| `domains/secrets/parts/services/<name>-*.age` | CREATE via `agenix -e` |
| `machines/server/config.nix` | EDIT — enable the service |

---

*End of reference document.*
*Paths are absolute; all code blocks show real file content from the live repo.*
