# HWC Server Networking Architecture

**Comprehensive Deep Dive into hwc-server Network Configuration**

Generated: 2025-11-06
Machine: `hwc-server`
NixOS Configuration: HWC Charter v6.0

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Network Topology Overview](#network-topology-overview)
3. [Network Zones & Address Spaces](#network-zones--address-spaces)
4. [Service Architecture](#service-architecture)
5. [Container Networking Deep Dive](#container-networking-deep-dive)
6. [Caddy Reverse Proxy Architecture](#caddy-reverse-proxy-architecture)
7. [VPN Routing with Gluetun](#vpn-routing-with-gluetun)
8. [Address Usage Decision Tree](#address-usage-decision-tree)
9. [Service Communication Matrix](#service-communication-matrix)
10. [TLS & Certificate Management](#tls--certificate-management)
11. [Troubleshooting Guide](#troubleshooting-guide)
12. [Configuration Patterns](#configuration-patterns)

---

## Executive Summary

Your `hwc-server` runs a sophisticated multi-layered networking architecture with:

- **Native NixOS services** (Jellyfin, Immich, Navidrome, CouchDB, Frigate)
- **Podman containers** (13 containerized services)
- **VPN routing** via Gluetun container for torrenting
- **Reverse proxy** via native Caddy with Tailscale TLS
- **4 distinct network zones** with specific routing patterns

**The Golden Rule**: Services on the server communicate via `localhost` (127.0.0.1), regardless of whether they're native or containerized. External clients use Tailscale (`100.115.126.41`).

---

## Network Topology Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         HWC-SERVER                                  │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                    ZONE 1: Physical Network                    │ │
│  │                    eno1: 192.168.1.13/24                      │ │
│  │                    (Home LAN - Router Gateway)                 │ │
│  └─────────────────────────┬─────────────────────────────────────┘ │
│                            │                                         │
│  ┌─────────────────────────┴─────────────────────────────────────┐ │
│  │                   ZONE 2: Loopback (localhost)                 │ │
│  │                     127.0.0.1 (lo interface)                   │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │ Native Svcs  │  │ Caddy Proxy  │  │  Containers  │        │ │
│  │  │  (systemd)   │  │   (native)   │  │   (podman)   │        │ │
│  │  │              │  │              │  │              │        │ │
│  │  │ Jellyfin     │  │ Port 80/443  │  │ Port-mapped  │        │ │
│  │  │ :8096        │◄─┤ Routing      │◄─┤ to localhost │        │ │
│  │  │ Immich       │  │              │  │              │        │ │
│  │  │ :2283        │  │ TLS via      │  │ qBittorrent  │        │ │
│  │  │ Navidrome    │  │ Tailscale    │  │ Prowlarr     │        │ │
│  │  │ :4533        │  │              │  │ Sonarr, etc. │        │ │
│  │  │ CouchDB      │  │              │  │              │        │ │
│  │  │ :5984        │  │              │  │              │        │ │
│  │  │ Frigate      │  │              │  │              │        │ │
│  │  │ :5000        │  │              │  │              │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                            │                                         │
│  ┌─────────────────────────┴─────────────────────────────────────┐ │
│  │              ZONE 3: Container Network (Podman)                │ │
│  │                   podman1: 10.89.0.1/24                        │ │
│  │                   (media-network bridge)                        │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐              │ │
│  │  │ Gluetun    │  │ Prowlarr   │  │ Sonarr     │              │ │
│  │  │ 10.89.0.x  │  │ 10.89.0.x  │  │ 10.89.0.x  │              │ │
│  │  │ (VPN GW)   │  │            │  │            │              │ │
│  │  │            │  │            │  │            │              │ │
│  │  │ Exposes:   │  │ Radarr     │  │ Lidarr     │              │ │
│  │  │ :8080 qBT  │  │ 10.89.0.x  │  │ 10.89.0.x  │              │ │
│  │  │ :8081 SAB  │  │            │  │            │              │ │
│  │  │            │  │ Jellyseerr │  │ SLSKD      │              │ │
│  │  │ Contains:  │  │ 10.89.0.x  │  │ 10.89.0.x  │              │ │
│  │  │ qBittorrent│  │            │  │            │              │ │
│  │  │ SABnzbd    │  │ Soularr    │  │            │              │ │
│  │  └────────────┘  └────────────┘  └────────────┘              │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                            │                                         │
│  ┌─────────────────────────┴─────────────────────────────────────┐ │
│  │              ZONE 4: VPN Network (Tailscale)                   │ │
│  │                tailscale0: 100.115.126.41/32                   │ │
│  │                hwc.ocelot-wahoo.ts.net                         │ │
│  │  • Encrypted mesh VPN                                          │ │
│  │  • TLS certificate provider for Caddy                          │ │
│  │  • Remote access endpoint for all services                     │ │
│  │  • Tagged as "tag:server" for ACL control                      │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

        ▲
        │ Tailscale VPN (encrypted)
        │
┌───────┴────────┐
│  hwc-laptop    │
│  Client Access │
│  via Tailscale │
│                │
│  /etc/hosts:   │
│  100.115.126.41│
│  *.local       │
└────────────────┘
```

---

## Network Zones & Address Spaces

### Zone 1: Physical Network (eno1)

**Address**: `192.168.1.13/24`
**Interface**: `eno1` (Ethernet)
**Purpose**: Physical home LAN connectivity

**When to use**:
- ❌ **NEVER** for service configuration
- ✅ Only for router connectivity and internet access
- ✅ Tailscale tunnel establishment

**Traffic flow**:
- Outbound internet traffic (via router 192.168.1.1)
- Tailscale encrypted tunnel initiation
- DHCP client for IP assignment

---

### Zone 2: Loopback (localhost)

**Address**: `127.0.0.1` or `localhost`
**Interface**: `lo` (loopback)
**Purpose**: **Primary inter-service communication**

**When to use**:
- ✅ **ALWAYS** for server-internal service communication
- ✅ Container port-mapped services talking to native services
- ✅ Native services talking to containers (via published ports)
- ✅ Caddy reverse proxy upstream targets

**Why this works**:
1. **Container port publishing**: Podman publishes container ports to `127.0.0.1:<port>`
2. **Security**: Services not exposed externally unless explicitly configured
3. **Performance**: Kernel-optimized loopback routing
4. **Simplicity**: No need to track dynamic container IPs

**Example configurations**:
```nix
# Container publishes to localhost
ports = [ "127.0.0.1:8989:8989" ];  # Sonarr

# Caddy proxies from localhost
upstream = "http://127.0.0.1:8989";  # Sonarr

# Another service connects via localhost
url = "http://localhost:8989";  # Prowlarr → Sonarr
```

---

### Zone 3: Container Network (podman1)

**Address**: `10.89.0.1/24` (gateway) + dynamic IPs for containers
**Interface**: `podman1` (bridge)
**Network Name**: `media-network` (Podman named network)
**Purpose**: Container-to-container networking

**When to use**:
- ✅ Podman internal DNS resolution (containers can use hostnames)
- ✅ Container-to-container direct communication
- ❌ **NOT** for host-to-container (use `localhost` instead)
- ❌ **NOT** for configuration (IPs are dynamic)

**Containers on this network**:
- Gluetun (VPN gateway)
- Prowlarr, Sonarr, Radarr, Lidarr (media management)
- Jellyseerr (media requests)
- SLSKD, Soularr (Soulseek integration)

**Special cases**:
- **qBittorrent**: Uses `--network=container:gluetun` (shares Gluetun's network namespace, not on media-network directly)
- **SABnzbd**: Uses `--network=container:gluetun` (shares Gluetun's network namespace)

**DNS resolution**:
```bash
# Inside prowlarr container
ping sonarr  # ✅ Resolves to 10.89.0.x via Podman DNS
curl http://sonarr:8989  # ✅ Works for container-to-container
```

**Port exposure flow**:
```
Container App → Container Port → Host Localhost Port → External Access
Sonarr:8989  →  10.89.0.x:8989 → 127.0.0.1:8989    → (via Caddy)
```

---

### Zone 4: VPN Network (tailscale0)

**Address**: `100.115.126.41/32`
**Interface**: `tailscale0` (WireGuard tunnel)
**Hostname**: `hwc.ocelot-wahoo.ts.net`
**Purpose**: Secure remote access and TLS certificate provisioning

**When to use**:
- ✅ Client devices accessing server services
- ✅ Laptop `/etc/hosts` entries (map `*.local` to this IP)
- ✅ Caddy TLS certificate retrieval (`get_certificate tailscale`)
- ❌ **NOT** for server-internal service communication

**Key features**:
1. **Encrypted mesh VPN**: All traffic encrypted end-to-end
2. **Automatic TLS**: Tailscale provides valid TLS certs for `*.ts.net` domains
3. **ACL-controlled**: Server tagged as `tag:server` for access control
4. **Route advertisement**: Server accepts routes from Tailscale network

**Client access pattern**:
```bash
# On hwc-laptop /etc/hosts:
100.115.126.41 sonarr.local radarr.local caddy.local
100.115.126.41 hwc.ocelot-wahoo.ts.net

# Browser access:
https://hwc.ocelot-wahoo.ts.net/sonarr  # ✅ Via Caddy subpath
https://hwc.ocelot-wahoo.ts.net:5543    # ✅ Via Caddy dedicated port (Jellyseerr)
```

---

## Service Architecture

### Native NixOS Services

These services run directly on the server via systemd (not containerized).

| Service | Port | Purpose | GPU | Firewall | Reverse Proxy |
|---------|------|---------|-----|----------|---------------|
| **Jellyfin** | 8096 | Media streaming | ✅ NVIDIA | ✅ TCP/UDP 7359, TCP 8096 | ✅ `/media` (planned) |
| **Immich** | 2283 | Photo management | ✅ NVIDIA | ✅ Tailscale-only | ❌ Direct port access |
| **Navidrome** | 4533 | Music streaming | ❌ | ✅ TCP 4533 | ✅ `/music` |
| **CouchDB** | 5984 | Obsidian sync | ❌ | ❌ (localhost only) | ✅ `/sync` |
| **Frigate** | 5000 | Camera NVR | ✅ ONNX/CUDA | ✅ TCP 5000 (Tailscale) | ❌ Direct port access |
| **Caddy** | 80, 443 | Reverse proxy | ❌ | ✅ TCP 80, 443 | N/A (is the proxy) |

**Why native services?**
1. **External device access**: Jellyfin needs LAN discovery for Roku TVs
2. **GPU acceleration**: Direct hardware access without container complexity
3. **System integration**: Better systemd integration, easier backup
4. **Performance**: No container networking overhead

**Service locations**:
```nix
# Configuration files
domains/server/jellyfin/index.nix       # Native Jellyfin service
domains/server/immich/index.nix         # Native Immich service
domains/server/navidrome/index.nix      # Native Navidrome service
domains/server/couchdb/index.nix        # Native CouchDB service
domains/server/frigate/                 # Native Frigate NVR

# Enabled in
profiles/server.nix                     # Service enablement
```

---

### Containerized Services (Podman)

These services run in Podman containers on the `media-network` bridge.

#### Download Clients (VPN-routed via Gluetun)

| Container | Internal Port | Exposed Port | Network Mode | Purpose |
|-----------|---------------|--------------|--------------|---------|
| **Gluetun** | N/A | 8080, 8081 | `media-network` | ProtonVPN gateway |
| **qBittorrent** | 8080 | 8080 (via Gluetun) | `container:gluetun` | Torrent client |
| **SABnzbd** | 8085 | 8081 (via Gluetun) | `container:gluetun` | Usenet client |

**VPN routing architecture**:
```
qBittorrent → shares network namespace → Gluetun → ProtonVPN → Internet
SABnzbd    → shares network namespace → Gluetun → ProtonVPN → Internet
```

**Port mapping**:
- Gluetun exposes `:8080` → qBittorrent's internal `:8080`
- Gluetun exposes `:8081` → SABnzbd's internal `:8085`
- Host accesses via `localhost:8080` and `localhost:8081`

#### Media Management (*arr Stack)

| Container | Port | Network Mode | Purpose |
|-----------|------|--------------|---------|
| **Prowlarr** | 9696 | `media-network` | Indexer manager |
| **Sonarr** | 8989 | `media-network` | TV show automation |
| **Radarr** | 7878 | `media-network` | Movie automation |
| **Lidarr** | 8686 | `media-network` | Music automation |
| **Jellyseerr** | 5055 | `media-network` | Media requests |

**Inter-service communication**:
```nix
# Sonarr connects to Prowlarr
# Inside Sonarr container:
Prowlarr URL: http://localhost:9696  # ✅ Via port-mapped localhost

# Prowlarr connects to Sonarr
# Inside Prowlarr container:
Sonarr URL: http://localhost:8989    # ✅ Via port-mapped localhost
```

#### Specialized Services

| Container | Port | Network Mode | Purpose |
|-----------|------|--------------|---------|
| **SLSKD** | 5031 | `media-network` | Soulseek client |
| **Soularr** | N/A | `media-network` | Soulseek → Lidarr automation |

---

### Service Configuration Locations

```
domains/server/
├── containers/
│   ├── _shared/
│   │   ├── lib.nix              # Container builder utilities
│   │   ├── network.nix          # media-network creation
│   │   └── caddy.nix            # Caddy reverse proxy config
│   ├── gluetun/
│   │   ├── options.nix
│   │   └── parts/
│   │       ├── config.nix       # VPN container definition
│   │       └── scripts.nix      # Environment file setup
│   ├── qbittorrent/
│   │   ├── options.nix          # network.mode = "vpn"
│   │   └── parts/config.nix     # --network=container:gluetun
│   ├── prowlarr/
│   │   ├── options.nix          # network.mode = "media"
│   │   └── parts/config.nix
│   ├── sonarr/
│   ├── radarr/
│   ├── lidarr/
│   ├── jellyseerr/
│   ├── slskd/
│   └── soularr/
├── jellyfin/index.nix           # Native service
├── immich/index.nix             # Native service
├── navidrome/index.nix          # Native service
├── couchdb/index.nix            # Native service
├── frigate/                     # Native service
└── routes.nix                   # Caddy routing definitions

profiles/server.nix              # Service enablement
machines/server/config.nix       # Machine-specific overrides
```

---

## Container Networking Deep Dive

### Network Modes

Your containers use two primary network modes:

#### 1. Media Network Mode (`media-network`)

**What it is**: Standard Podman bridge network with DNS resolution

**Configuration**:
```nix
extraOptions = [ "--network=media-network" ];
```

**Containers using this**:
- Prowlarr, Sonarr, Radarr, Lidarr
- Jellyseerr
- SLSKD, Soularr
- Gluetun (VPN gateway)

**Port publishing**:
```nix
# Standard port publishing to localhost
ports = [ "127.0.0.1:8989:8989" ];  # Sonarr
ports = [ "127.0.0.1:7878:7878" ];  # Radarr
ports = [ "127.0.0.1:9696:9696" ];  # Prowlarr
```

**How it works**:
1. Podman creates bridge `podman1` at `10.89.0.1/24`
2. Each container gets dynamic IP from `10.89.0.0/24` pool
3. Podman DNS resolves container names (e.g., `sonarr` → `10.89.0.x`)
4. Ports published to host's `127.0.0.1:<port>`
5. External access via Caddy reverse proxy

**Network flow**:
```
Container (10.89.0.x:8989) → Podman NAT → localhost:8989 → Caddy → External
```

---

#### 2. VPN Container Network Mode (`container:gluetun`)

**What it is**: Shared network namespace with Gluetun VPN container

**Configuration**:
```nix
extraOptions = [ "--network=container:gluetun" ];
```

**Containers using this**:
- qBittorrent
- SABnzbd

**How it works**:
1. Gluetun container starts first on `media-network`
2. Gluetun establishes ProtonVPN connection (Netherlands)
3. qBittorrent/SABnzbd containers **share Gluetun's network stack**
4. All traffic from qBittorrent/SABnzbd goes through VPN tunnel
5. Gluetun container exposes ports to host (`:8080`, `:8081`)

**Network flow**:
```
qBittorrent (no IP, uses Gluetun's stack) → Gluetun (10.89.0.x) → ProtonVPN → Internet
                                           ↓
                                    Gluetun exposes :8080
                                           ↓
                                    Host localhost:8080
                                           ↓
                                    Caddy /qbt → External
```

**Why this pattern?**:
- ✅ All torrent traffic goes through VPN (no leaks possible)
- ✅ If VPN drops, qBittorrent loses all connectivity (fail-safe)
- ✅ No complex routing rules or iptables needed
- ✅ Single VPN connection for multiple clients

**Dependencies**:
```nix
# qBittorrent must wait for Gluetun
systemd.services.podman-qbittorrent = {
  after = [ "podman-gluetun.service" ];
  wants = [ "podman-gluetun.service" ];
};

# Container runtime dependency
dependsOn = [ "gluetun" ];
```

---

### Container Port Publishing Rules

**Format**: `"<host-ip>:<host-port>:<container-port>"`

**Examples**:
```nix
# ✅ CORRECT: Bind to localhost only (secure)
ports = [ "127.0.0.1:8989:8989" ];

# ✅ CORRECT: Bind to all interfaces (when needed for LAN access)
ports = [ "0.0.0.0:8080:8080" ];

# ❌ WRONG: No host IP specified (defaults to 0.0.0.0, exposes publicly)
ports = [ "8989:8989" ];

# ⚠️ VPN mode: Don't specify ports (Gluetun handles exposure)
# qBittorrent/SABnzbd don't have their own port declarations
```

**Your configuration pattern**:
```nix
# Standard container (Sonarr)
ports = lib.optionals (cfg.network.mode != "vpn") [
  "127.0.0.1:${toString cfg.webPort}:${toString cfg.webPort}"
];

# VPN container (qBittorrent)
ports = [];  # No ports, uses Gluetun's exposure
```

---

### Container Volume Mounts

**Storage layout**:
```
/mnt/hot/                       # SSD hot storage (config.hwc.paths.hot)
├── downloads/                  # Download staging
│   ├── incomplete/             # SLSKD active downloads
│   └── complete/               # SLSKD completed downloads
├── processing/                 # *arr processing directories
│   ├── sonarr-temp/
│   ├── radarr-temp/
│   └── lidarr-temp/
└── events/                     # SABnzbd post-processing triggers

/mnt/media/                     # HDD media storage (config.hwc.paths.media)
├── tv/                         # Sonarr library
├── movies/                     # Radarr library
├── music/                      # Lidarr/Navidrome library
└── pictures/                   # Immich library

/opt/downloads/                 # Container configs
├── qbittorrent/               # qBittorrent config
├── sonarr/                    # Sonarr config
├── scripts/                   # Post-processing scripts
└── .env                       # Gluetun VPN credentials (generated from agenix)
```

**Example volume mounts**:
```nix
# Sonarr container
volumes = [
  "/opt/downloads/sonarr:/config"              # App config
  "${paths.media}/tv:/tv"                      # TV library (read/write)
  "${paths.hot}/downloads:/downloads"          # Downloads (read/write)
  "${paths.hot}/processing/sonarr-temp:/temp"  # Processing temp
];

# qBittorrent container
volumes = [
  "/opt/downloads/qbittorrent:/config"
  "${paths.hot}/downloads:/downloads"
  "/opt/downloads/scripts:/scripts:ro"         # Read-only scripts
  "${paths.hot}/events:/mnt/hot/events"        # Event triggers
];
```

---

## Caddy Reverse Proxy Architecture

Caddy is the central reverse proxy, providing:
1. **TLS termination** via Tailscale certificates
2. **Subpath routing** for services supporting URL bases
3. **Port-based routing** for subpath-hostile apps
4. **WebSocket support** for real-time applications

### Configuration Structure

**Location**: `domains/server/containers/_shared/caddy.nix`

**Route definition**: `domains/server/routes.nix`

```nix
hwc.services.shared.routes = [
  {
    name = "sonarr";
    mode = "subpath";              # Subpath routing
    path = "/sonarr";
    upstream = "http://127.0.0.1:8989";
    needsUrlBase = true;           # App has URL base setting
    headers = { "X-Forwarded-Prefix" = "/sonarr"; };
  }
  {
    name = "jellyseerr";
    mode = "port";                 # Dedicated port routing
    port = 5543;
    upstream = "http://127.0.0.1:5055";
  }
];
```

---

### Routing Modes

#### Subpath Mode (`mode = "subpath"`)

**When to use**:
- ✅ App supports URL base configuration
- ✅ Want to consolidate multiple services under one domain
- ✅ Clean URLs without port numbers

**How it works**:
```
Client Request: https://hwc.ocelot-wahoo.ts.net/sonarr
                       ↓
Caddy receives request on port 443
                       ↓
Matches path "/sonarr*"
                       ↓
Forward to upstream: http://127.0.0.1:8989
                       ↓
Sonarr receives request (with URL base configured)
```

**Two subpath variants**:

1. **Preserve path** (`needsUrlBase = true`):
   - App expects to receive full path including prefix
   - Sonarr, Radarr, Lidarr, Prowlarr use this
   - App's URL base setting must match Caddy path

```nix
# Caddy config
@sonarr path /sonarr*
handle @sonarr {
  reverse_proxy http://127.0.0.1:8989
}

# Sonarr config must have:
URL Base = /sonarr
```

2. **Strip path** (`needsUrlBase = false`):
   - App expects requests at root, Caddy strips prefix
   - qBittorrent uses this (buggy URL base implementation)

```nix
# Caddy config
handle_path /qbt* {
  reverse_proxy http://127.0.0.1:8080
}

# qBittorrent receives request as if it came to "/"
```

**Services using subpath mode**:
- `/sonarr` → Sonarr (preserve path)
- `/radarr` → Radarr (preserve path)
- `/lidarr` → Lidarr (preserve path)
- `/prowlarr` → Prowlarr (preserve path)
- `/qbt` → qBittorrent (strip path)
- `/sab` → SABnzbd (preserve path)
- `/music` → Navidrome (preserve path)
- `/sync` → CouchDB (preserve path)

---

#### Port Mode (`mode = "port"`)

**When to use**:
- ✅ App is subpath-hostile (Jellyseerr, Immich, Frigate, SLSKD)
- ✅ WebSocket/SSE issues with subpaths
- ✅ App serves assets from hardcoded paths

**How it works**:
```
Client Request: https://hwc.ocelot-wahoo.ts.net:5543
                       ↓
Caddy receives request on dedicated port 5543
                       ↓
Forward to upstream: http://127.0.0.1:5055
                       ↓
Jellyseerr receives request (thinks it's at root)
```

**Caddy configuration**:
```nix
# Dedicated TLS listener per port
hwc.ocelot-wahoo.ts.net:5543 {
  tls { get_certificate tailscale }
  encode zstd gzip
  reverse_proxy http://127.0.0.1:5055
}
```

**Services using port mode**:
- `:5543` → Jellyseerr (port 5055)
- `:7443` → Immich (port 2283)
- `:5443` → Frigate (port 5000)
- `:8443` → SLSKD (port 5031)

**Firewall handling**:
```nix
# Caddy automatically opens firewall for port-mode services
networking.firewall.allowedTCPPorts = [ 80 443 5543 7443 5443 8443 ];
```

---

### TLS Configuration

**Certificate source**: Tailscale (via `get_certificate tailscale`)

**How it works**:
1. Server configured with `services.tailscale.permitCertUid = "caddy";`
2. Caddy requests cert via `tls { get_certificate tailscale }`
3. Tailscale generates valid TLS cert for `*.ocelot-wahoo.ts.net`
4. Caddy uses cert for all HTTPS connections

**Certificate scope**:
- ✅ Valid for `hwc.ocelot-wahoo.ts.net` and all ports
- ✅ Trusted by all clients (Tailscale CA)
- ✅ Automatic renewal (handled by Tailscale)
- ❌ Only works on Tailscale network

**Caddyfile structure**:
```nix
extraConfig = ''
  # Localhost listener (testing, no TLS)
  localhost {
    tls internal
    encode zstd gzip
    # ... subpath routes ...
  }

  # Main Tailscale domain (TLS via Tailscale)
  hwc.ocelot-wahoo.ts.net {
    tls { get_certificate tailscale }
    encode zstd gzip
    # ... subpath routes ...
  }

  # Port-based services (each gets own TLS listener)
  hwc.ocelot-wahoo.ts.net:5543 {
    tls { get_certificate tailscale }
    encode zstd gzip
    reverse_proxy http://127.0.0.1:5055
  }
'';
```

---

### Upstream Configuration Pattern

**The Critical Rule**: Always use `http://` (not `https://`) for localhost upstreams.

**Why**:
- Native services (Jellyfin, Navidrome, etc.) run plain HTTP on localhost
- Containers expose plain HTTP on localhost
- Caddy handles TLS termination externally
- Internal traffic doesn't need encryption (same machine)

**Correct patterns**:
```nix
# ✅ CORRECT: HTTP to localhost
upstream = "http://127.0.0.1:8989";  # Sonarr
upstream = "http://127.0.0.1:8096";  # Jellyfin
upstream = "http://127.0.0.1:5055";  # Jellyseerr

# ❌ WRONG: HTTPS to localhost (will fail - no TLS cert on upstream)
upstream = "https://127.0.0.1:8989";
```

**Why localhost worked after TLS fix**:
- **Before**: Caddy tried to validate upstream TLS (services had no certs)
- **After**: Caddy explicitly configured to use HTTP for upstreams
- The "TLS fix" was clarifying `http://` in upstream declarations

---

### WebSocket Support

**Enabled by default** for all routes:
```nix
reverse_proxy ${r.upstream} {
  flush_interval -1  # ✅ Enables WebSocket support
}
```

**Services requiring WebSockets**:
- Jellyseerr (real-time notifications)
- Frigate (live camera feeds)
- Immich (live photo uploads)

---

## VPN Routing with Gluetun

Gluetun is your VPN gateway container, routing qBittorrent and SABnzbd through ProtonVPN.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Server Host                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │          Podman media-network (10.89.0.0/24)        │   │
│  │                                                     │   │
│  │  ┌───────────────────────────────────────────┐     │   │
│  │  │         Gluetun Container                 │     │   │
│  │  │         IP: 10.89.0.x                     │     │   │
│  │  │                                           │     │   │
│  │  │  ┌─────────────────────────────────┐     │     │   │
│  │  │  │   OpenVPN Client                │     │     │   │
│  │  │  │   → ProtonVPN Netherlands       │     │     │   │
│  │  │  │   → Encrypted tunnel            │     │     │   │
│  │  │  └─────────────────────────────────┘     │     │   │
│  │  │            ▲                              │     │   │
│  │  │            │ (shares network namespace)   │     │   │
│  │  │            ├─────────────────┐            │     │   │
│  │  │            │                 │            │     │   │
│  │  │  ┌─────────┴─────┐  ┌───────┴────────┐   │     │   │
│  │  │  │ qBittorrent   │  │   SABnzbd      │   │     │   │
│  │  │  │ (no own IP)   │  │   (no own IP)  │   │     │   │
│  │  │  │ Port: 8080    │  │   Port: 8085   │   │     │   │
│  │  │  └───────────────┘  └────────────────┘   │     │   │
│  │  │                                           │     │   │
│  │  │  Exposed ports:                           │     │   │
│  │  │  0.0.0.0:8080 → qBittorrent :8080         │     │   │
│  │  │  0.0.0.0:8081 → SABnzbd :8085             │     │   │
│  │  └───────────────────────────────────────────┘     │   │
│  │                        │                           │   │
│  └────────────────────────┼───────────────────────────┘   │
│                           │                               │
│                           ↓                               │
│                    Host localhost:8080, :8081             │
│                           │                               │
│                           ↓                               │
│                    Caddy Reverse Proxy                    │
└─────────────────────────────────────────────────────────────┘
```

---

### Gluetun Configuration

**Location**: `domains/server/containers/gluetun/parts/config.nix`

**Key configuration**:
```nix
virtualisation.oci-containers.containers.gluetun = {
  image = "ghcr.io/qdm12/gluetun";
  autoStart = true;

  extraOptions = [
    "--cap-add=NET_ADMIN"          # Required for VPN routing
    "--cap-add=SYS_MODULE"         # Required for kernel modules
    "--device=/dev/net/tun:/dev/net/tun"  # TUN device for VPN
    "--network=media-network"      # Connect to Podman network
    "--privileged"                 # Required for VPN functionality
  ];

  ports = [
    "0.0.0.0:8080:8080"  # qBittorrent Web UI
    "0.0.0.0:8081:8085"  # SABnzbd Web UI (internal :8085, external :8081)
  ];

  environmentFiles = [ "/opt/downloads/.env" ];  # VPN credentials
};
```

**Environment file generation** (from agenix secrets):
```nix
systemd.services.gluetun-env-setup = {
  script = ''
    VPN_USERNAME=$(cat ${config.age.secrets.vpn-username.path})
    VPN_PASSWORD=$(cat ${config.age.secrets.vpn-password.path})
    cat > /opt/downloads/.env <<EOF
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=$VPN_USERNAME
OPENVPN_PASSWORD=$VPN_PASSWORD
SERVER_COUNTRIES=Netherlands
HEALTH_VPN_DURATION_INITIAL=30s
HEALTH_TARGET_ADDRESS=1.1.1.1:443
EOF
  '';
};
```

---

### qBittorrent & SABnzbd Network Sharing

**qBittorrent configuration**:
```nix
virtualisation.oci-containers.containers.qbittorrent = {
  extraOptions = [
    "--network=container:gluetun"  # ✅ Share Gluetun's network namespace
  ];

  # ❌ NO port declarations (Gluetun exposes them)
  ports = [];

  # ✅ Dependency ensures Gluetun starts first
  dependsOn = [ "gluetun" ];
};

systemd.services.podman-qbittorrent = {
  after = [ "podman-gluetun.service" ];
  wants = [ "podman-gluetun.service" ];
};
```

**SABnzbd configuration**: (same pattern)
```nix
virtualisation.oci-containers.containers.sabnzbd = {
  extraOptions = [ "--network=container:gluetun" ];
  ports = [];
  dependsOn = [ "gluetun" ];
};
```

---

### Traffic Flow

**Outbound torrent traffic**:
```
qBittorrent → (shares Gluetun network) → Gluetun container →
ProtonVPN tunnel → Netherlands VPN server → Internet
```

**Inbound Web UI access**:
```
Client browser → Tailscale → hwc.ocelot-wahoo.ts.net/qbt →
Caddy → localhost:8080 → Gluetun container port 8080 →
qBittorrent app (in shared namespace)
```

---

### VPN Health Monitoring

**Gluetun health checks**:
```bash
# Health check configuration
HEALTH_VPN_DURATION_INITIAL=30s
HEALTH_TARGET_ADDRESS=1.1.1.1:443

# Check VPN status
sudo podman exec gluetun cat /tmp/gluetun/vpn-status

# Check public IP (should be VPN IP, not home IP)
sudo podman exec qbittorrent curl ifconfig.me
# Expected: ProtonVPN Netherlands IP (NOT 192.168.1.13)
```

---

### Fail-Safe Behavior

**If VPN drops**:
1. Gluetun loses ProtonVPN connection
2. qBittorrent/SABnzbd have **no network access** (no fallback to home IP)
3. Containers cannot leak home IP address
4. Web UI remains accessible via localhost (not routed through VPN)

**Recovery**:
```bash
# Restart Gluetun to reconnect VPN
sudo systemctl restart podman-gluetun.service

# Dependent containers auto-restart if needed
sudo systemctl restart podman-qbittorrent.service
sudo systemctl restart podman-sabnzbd.service
```

---

## Address Usage Decision Tree

Use this flowchart to determine which address to use when configuring services:

```
┌─────────────────────────────────────────────────────────────┐
│  Configuring a service or container?                        │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ↓
┌────────────────────────────────────────────────────────────┐
│  Where is the CLIENT that needs to connect?                │
└────────┬───────────────────────────────────┬───────────────┘
         │                                   │
         │ CLIENT: On the server itself      │ CLIENT: External
         │ (server-to-server)                │ (laptop, phone)
         ↓                                   ↓
┌────────────────────────────┐    ┌──────────────────────────┐
│  Use: localhost/127.0.0.1  │    │  Use: Tailscale address  │
│                            │    │  100.115.126.41          │
│  Examples:                 │    │  or                      │
│  • Caddy upstream          │    │  hwc.ocelot-wahoo.ts.net │
│  • *arr to Prowlarr        │    │                          │
│  • Prowlarr to Sonarr      │    │  Examples:               │
│  • Sonarr to qBittorrent   │    │  • Laptop browser        │
│  • Service API calls       │    │  • Phone Jellyfin app    │
│                            │    │  • Laptop /etc/hosts     │
│  Format:                   │    │                          │
│  http://localhost:8989     │    │  Format:                 │
│  http://127.0.0.1:8989     │    │  https://hwc.ocelot-...  │
└────────────────────────────┘    └──────────────────────────┘
```

**Common mistakes to avoid**:
- ❌ Using `192.168.1.13` for anything (physical LAN IP, rarely needed)
- ❌ Using `10.89.0.x` in config files (container IPs are dynamic)
- ❌ Using `100.115.126.41` for server-to-server comm (use localhost)
- ❌ Using `https://` for localhost upstreams (services run HTTP internally)

---

## Service Communication Matrix

This table shows how services communicate with each other:

| Source Service | Target Service | Address Used | Protocol | Reason |
|----------------|----------------|--------------|----------|---------|
| **Caddy** | Sonarr | `http://127.0.0.1:8989` | HTTP | Reverse proxy to container port |
| **Caddy** | Jellyfin | `http://127.0.0.1:8096` | HTTP | Reverse proxy to native service |
| **Caddy** | Navidrome | `http://127.0.0.1:4533` | HTTP | Reverse proxy to native service |
| **Prowlarr** | Sonarr | `http://localhost:8989` | HTTP | Indexer sync (both containers) |
| **Prowlarr** | Radarr | `http://localhost:7878` | HTTP | Indexer sync (both containers) |
| **Prowlarr** | Lidarr | `http://localhost:8686` | HTTP | Indexer sync (both containers) |
| **Sonarr** | Prowlarr | `http://localhost:9696` | HTTP | Search requests (both containers) |
| **Sonarr** | qBittorrent | `http://localhost:8080` | HTTP | Download client (container via Gluetun) |
| **Sonarr** | SABnzbd | `http://localhost:8081` | HTTP | Download client (container via Gluetun) |
| **Radarr** | qBittorrent | `http://localhost:8080` | HTTP | Download client (container via Gluetun) |
| **Lidarr** | SLSKD | `http://localhost:5031` | HTTP | Soulseek downloads (via Soularr) |
| **Jellyseerr** | Sonarr | `http://localhost:8989` | HTTP | Media requests (container to container) |
| **Jellyseerr** | Radarr | `http://localhost:7878` | HTTP | Media requests (container to container) |
| **Laptop** | Caddy | `https://hwc.ocelot-wahoo.ts.net` | HTTPS | Remote access via Tailscale |
| **Laptop** | Immich | `https://hwc.ocelot-wahoo.ts.net:7443` | HTTPS | Direct port access via Tailscale |
| **Laptop** | Frigate | `http://hwc.ocelot-wahoo.ts.net:5000` | HTTP | Direct port access (Tailscale-only firewall) |
| **Obsidian** | CouchDB | `https://hwc.ocelot-wahoo.ts.net/sync` | HTTPS | Sync via Caddy subpath |

**Key patterns**:
1. **Server-to-server**: Always `localhost` (both native and containers)
2. **Client-to-server**: Always Tailscale domain or IP
3. **Container-to-container**: Can use `localhost` (via port-mapped ports)
4. **VPN-routed**: qBittorrent/SABnzbd accessed via Gluetun-exposed ports on `localhost`

---

## TLS & Certificate Management

### Certificate Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│              Tailscale Certificate Authority                │
│              (Built into Tailscale network)                 │
└────────────────┬────────────────────────────────────────────┘
                 │ Issues certificates for
                 │
                 ↓
┌─────────────────────────────────────────────────────────────┐
│           *.ocelot-wahoo.ts.net Certificate                 │
│           Automatically renewed by Tailscale                │
│           Valid for all Tailscale clients                   │
└────────────────┬────────────────────────────────────────────┘
                 │ Caddy retrieves via
                 │ tls { get_certificate tailscale }
                 ↓
┌─────────────────────────────────────────────────────────────┐
│                      Caddy TLS Termination                  │
│  • Handles all HTTPS connections                            │
│  • Presents Tailscale cert to clients                       │
│  • Proxies to upstreams via HTTP (localhost)                │
└─────────────────────────────────────────────────────────────┘
```

### How TLS Works

**Certificate retrieval**:
```nix
# Server allows Caddy to request Tailscale certs
services.tailscale.permitCertUid = "caddy";

# Caddy requests cert for domain
services.caddy.extraConfig = ''
  hwc.ocelot-wahoo.ts.net {
    tls { get_certificate tailscale }  # Magic happens here
    # ...
  }
'';
```

**Certificate lifecycle**:
1. Caddy starts and requests cert via Tailscale API
2. Tailscale validates Caddy's identity (via `permitCertUid`)
3. Tailscale issues cert for `hwc.ocelot-wahoo.ts.net`
4. Caddy stores cert in `/var/lib/caddy`
5. Tailscale auto-renews before expiration
6. Caddy reloads automatically on renewal

**Certificate properties**:
- **Issuer**: Tailscale CA (trusted by Tailscale clients)
- **Subject**: `hwc.ocelot-wahoo.ts.net`
- **Validity**: 90 days (auto-renewed at 60 days)
- **SAN**: `*.ocelot-wahoo.ts.net` (covers all ports)
- **Trust**: Automatic (Tailscale manages client trust)

---

### Why Localhost Requires HTTP

**The problem**:
```
Caddy (HTTPS) → wants to verify upstream TLS → localhost:8989 (no TLS)
                                                      ↓
                                              Connection fails!
```

**The solution**:
```nix
# ✅ Explicitly use HTTP for localhost upstreams
upstream = "http://127.0.0.1:8989";

# Caddy knows not to expect TLS
reverse_proxy http://127.0.0.1:8989 {
  # No TLS validation needed
}
```

**Why this is secure**:
- Traffic between Caddy and upstreams stays on `lo` interface
- Loopback traffic never leaves the server
- No physical network exposure
- Kernel-internal routing (no wire traversal)
- External clients still get TLS (Caddy → Client)

---

### TLS Troubleshooting

**Issue**: "Cannot connect to service via HTTPS"

**Check**:
```bash
# 1. Verify Tailscale is running
sudo systemctl status tailscaled

# 2. Verify Caddy has certificate permission
sudo journalctl -u caddy | rg -i "tailscale"

# 3. Check Tailscale cert retrieval
sudo tailscale cert hwc.ocelot-wahoo.ts.net

# 4. Verify Caddy is using HTTP upstreams
sudo journalctl -u caddy | rg -i "upstream"
```

**Common fixes**:
```nix
# Fix 1: Ensure permitCertUid is set
services.tailscale.permitCertUid = "caddy";

# Fix 2: Ensure upstreams use http://
upstream = "http://127.0.0.1:8989";  # ✅ Not https://

# Fix 3: Restart Caddy after Tailscale changes
sudo systemctl restart caddy
```

---

## Troubleshooting Guide

### Container Cannot Reach Another Container

**Symptom**: Prowlarr cannot connect to Sonarr, or Sonarr cannot reach qBittorrent.

**Diagnosis**:
```bash
# Check if container is running
sudo podman ps | rg -i sonarr

# Check container network mode
sudo podman inspect sonarr | rg -i NetworkMode

# Test connectivity from within container
sudo podman exec prowlarr curl http://localhost:8989
```

**Solution**:
```nix
# ✅ Use localhost for inter-service communication
# In Prowlarr, configure Sonarr connection:
URL: http://localhost:8989

# NOT container IP (dynamic):
# URL: http://10.89.0.123:8989  # ❌ WRONG
```

---

### Service Not Accessible via Tailscale

**Symptom**: Cannot access `https://hwc.ocelot-wahoo.ts.net/sonarr` from laptop.

**Diagnosis**:
```bash
# 1. Check Tailscale connection
sudo tailscale status

# 2. Check Caddy is running
sudo systemctl status caddy

# 3. Check firewall
sudo iptables -L -n | rg -i "443"

# 4. Check Caddy config
sudo journalctl -u caddy | rg -i "error"

# 5. Test from server itself
curl http://localhost/sonarr
```

**Solution**:
```nix
# Ensure reverse proxy is enabled
hwc.services.reverseProxy.enable = true;

# Ensure route is defined
hwc.services.shared.routes = [
  {
    name = "sonarr";
    mode = "subpath";
    path = "/sonarr";
    upstream = "http://127.0.0.1:8989";
    needsUrlBase = true;
  }
];

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server
```

---

### VPN Not Working (qBittorrent Shows Home IP)

**Symptom**: qBittorrent leaks home IP instead of VPN IP.

**Diagnosis**:
```bash
# 1. Check Gluetun status
sudo podman ps | rg -i gluetun
sudo podman logs gluetun | tail -50

# 2. Check VPN connection
sudo podman exec gluetun cat /tmp/gluetun/vpn-status

# 3. Check public IP from qBittorrent
sudo podman exec qbittorrent curl ifconfig.me
# Should show ProtonVPN IP, not 192.168.1.13

# 4. Check network namespace sharing
sudo podman inspect qbittorrent | rg -i NetworkMode
# Should show: "container:gluetun"
```

**Solution**:
```nix
# Ensure qBittorrent uses Gluetun network
virtualisation.oci-containers.containers.qbittorrent = {
  extraOptions = [
    "--network=container:gluetun"  # ✅ Critical
  ];
  dependsOn = [ "gluetun" ];
};

# Restart containers
sudo systemctl restart podman-gluetun.service
sudo systemctl restart podman-qbittorrent.service
```

---

### Port Already in Use

**Symptom**: `Error: address already in use`

**Diagnosis**:
```bash
# Find what's using the port
sudo ss -tulpn | rg ":8989"

# Check for port conflicts
sudo podman ps --format "{{.Names}} {{.Ports}}"
```

**Solution**:
```bash
# Option 1: Stop conflicting service
sudo systemctl stop conflicting-service

# Option 2: Change port in container config
# Edit container options.nix:
webPort = 8990;  # Use different port

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server
```

---

### Caddy Returns 502 Bad Gateway

**Symptom**: Caddy running, but upstream service returns 502.

**Diagnosis**:
```bash
# 1. Check if upstream service is running
sudo podman ps | rg -i sonarr
sudo systemctl status jellyfin  # for native services

# 2. Check if service is listening on expected port
sudo ss -tulpn | rg ":8989"

# 3. Test upstream directly
curl http://localhost:8989

# 4. Check Caddy logs
sudo journalctl -u caddy | rg -i "502"
```

**Solution**:
```nix
# Ensure upstream port matches container/service port
# In routes.nix:
upstream = "http://127.0.0.1:8989";  # Must match actual port

# Ensure service is running
sudo systemctl restart podman-sonarr.service
# or
sudo systemctl restart jellyfin.service
```

---

### Container Won't Start After Rebuild

**Symptom**: `systemctl status podman-sonarr` shows failed state.

**Diagnosis**:
```bash
# Check systemd unit logs
sudo journalctl -u podman-sonarr -n 100

# Check Podman logs
sudo podman logs sonarr

# Check for dependency issues
sudo systemctl list-dependencies podman-sonarr

# Check volume permissions
ls -la /opt/downloads/sonarr
ls -la /mnt/media/tv
```

**Common issues**:
```bash
# Issue 1: Volume path doesn't exist
# Fix:
sudo mkdir -p /opt/downloads/sonarr
sudo chown 1000:1000 /opt/downloads/sonarr

# Issue 2: Network not ready
# Fix: Ensure dependency in config
systemd.services.podman-sonarr = {
  after = [ "init-media-network.service" ];
  wants = [ "init-media-network.service" ];
};

# Issue 3: Secrets not available
# Fix: Check agenix secrets
sudo ls -la /run/agenix/
```

---

## Configuration Patterns

### Adding a New Container Service

**Step 1: Create container module**
```nix
# domains/server/containers/newservice/options.nix
{ lib, ... }:
{
  options.hwc.services.containers.newservice = {
    enable = lib.mkEnableOption "newservice container";
    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/newservice:latest";
    };
    network.mode = lib.mkOption {
      type = lib.types.enum [ "media" "vpn" ];
      default = "media";
    };
    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8900;
    };
  };
}

# domains/server/containers/newservice/parts/config.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.newservice;
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.newservice = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--network=media-network"
      ];

      ports = [
        "127.0.0.1:${toString cfg.webPort}:${toString cfg.webPort}"
      ];

      volumes = [
        "/opt/downloads/newservice:/config"
      ];

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone;
      };
    };

    systemd.services.podman-newservice = {
      after = [ "init-media-network.service" ];
      wants = [ "init-media-network.service" ];
    };
  };
}

# domains/server/containers/newservice/index.nix
{ lib, config, pkgs, ... }:
{
  imports = [
    ./options.nix
    ./parts/config.nix
  ];
}
```

**Step 2: Add route to Caddy**
```nix
# domains/server/routes.nix
hwc.services.shared.routes = [
  # ... existing routes ...
  {
    name = "newservice";
    mode = "subpath";  # or "port" if subpath-hostile
    path = "/newservice";
    upstream = "http://127.0.0.1:8900";
    needsUrlBase = true;  # if app supports URL base
  }
];
```

**Step 3: Enable in server profile**
```nix
# profiles/server.nix
hwc.services.containers.newservice.enable = true;
```

**Step 4: Create config directory and rebuild**
```bash
sudo mkdir -p /opt/downloads/newservice
sudo chown 1000:1000 /opt/downloads/newservice

sudo nixos-rebuild switch --flake .#hwc-server
```

---

### Adding a New Native Service

**Example**: Adding a native service like Jellyfin

```nix
# domains/server/newservice/index.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.newservice;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    # Native service
    services.newservice = {
      enable = true;
      port = cfg.settings.port;
    };

    # Firewall
    networking.firewall.allowedTCPPorts = [ cfg.settings.port ];

    # GPU access (if needed)
    systemd.services.newservice = lib.mkIf cfg.gpu.enable {
      serviceConfig = {
        DeviceAllow = [
          "/dev/nvidia0 rw"
          "/dev/dri/renderD128 rw"
        ];
        SupplementaryGroups = [ "video" "render" ];
      };
    };
  };
}

# domains/server/newservice/options.nix
{ lib, ... }:
{
  options.hwc.server.newservice = {
    enable = lib.mkEnableOption "newservice";
    settings.port = lib.mkOption {
      type = lib.types.port;
      default = 9000;
    };
    gpu.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };
}
```

---

### Configuring a Service to Use Another Service

**Example**: Sonarr needs to connect to Prowlarr and qBittorrent

**In Sonarr Web UI**:

1. **Prowlarr Indexer**:
   - Go to Settings → Indexers
   - Add Prowlarr
   - URL: `http://localhost:9696`
   - API Key: (from Prowlarr)

2. **qBittorrent Download Client**:
   - Go to Settings → Download Clients
   - Add qBittorrent
   - URL: `http://localhost:8080`
   - Username/Password: (from qBittorrent)

**Why this works**:
- Both services publish ports to `localhost`
- Containers can access localhost via host network stack
- No need for container IPs or Podman DNS

---

## Summary & Best Practices

### The Golden Rules

1. **Server-to-server communication**: Always use `localhost` or `127.0.0.1`
2. **Client-to-server access**: Always use Tailscale address `100.115.126.41` or `hwc.ocelot-wahoo.ts.net`
3. **Upstream protocols**: Always use `http://` for localhost upstreams (Caddy handles TLS externally)
4. **Container networking**: Use `--network=media-network` unless VPN routing required
5. **VPN routing**: Use `--network=container:gluetun` for services needing VPN

### Address Usage Quick Reference

| Scenario | Address to Use | Example |
|----------|----------------|---------|
| Container talking to container | `http://localhost:<port>` | `http://localhost:8989` |
| Native service talking to container | `http://localhost:<port>` | `http://localhost:8989` |
| Container talking to native service | `http://localhost:<port>` | `http://localhost:8096` |
| Caddy upstream configuration | `http://127.0.0.1:<port>` | `http://127.0.0.1:8989` |
| Laptop accessing via Caddy | `https://hwc.ocelot-wahoo.ts.net/<path>` | `https://hwc.ocelot-wahoo.ts.net/sonarr` |
| Laptop direct port access | `https://hwc.ocelot-wahoo.ts.net:<port>` | `https://hwc.ocelot-wahoo.ts.net:5543` |

### Network Layers Summary

```
Layer 4: Tailscale VPN (100.115.126.41)
         ↓ Encrypted tunnel
         ↓ Client access point
         ↓
Layer 3: Host Network (192.168.1.13)
         ↓ Physical LAN
         ↓ Internet gateway
         ↓
Layer 2: Loopback (127.0.0.1)
         ↓ Service-to-service
         ↓ Caddy ↔ Upstreams
         ↓
Layer 1: Container Network (10.89.0.0/24)
         ↓ Container-to-container
         ↓ Podman DNS
         ↓ Port publishing to localhost
```

### Security Architecture

1. **Containers isolated**: Each container has its own namespace
2. **VPN fail-safe**: qBittorrent/SABnzbd cannot leak home IP
3. **Firewall protection**: Only necessary ports exposed
4. **TLS everywhere**: All external access uses Tailscale TLS
5. **Localhost-only binding**: Services not exposed to LAN unless needed
6. **Secrets management**: agenix for credentials, auto-generated env files

### Performance Considerations

1. **Loopback optimization**: Kernel-optimized, no network overhead
2. **Container resource limits**: `--memory=2g --cpus=1.0` per container
3. **Compression**: Caddy uses `zstd gzip` for all responses
4. **I/O scheduling**: `mq-deadline` for SSDs, `bfq` for HDDs
5. **Kernel tuning**: `vm.dirty_ratio`, `vm.swappiness` optimized for server workloads

---

## Conclusion

Your HWC server networking architecture is sophisticated but logically organized:

- **4 network zones** with clear boundaries and purposes
- **Native services** for external device access and GPU acceleration
- **Containerized services** for isolation and easy management
- **VPN routing** for privacy on torrent/usenet traffic
- **Caddy reverse proxy** for unified TLS termination and routing
- **Tailscale VPN** for secure remote access and certificate management

**The key insight**: Despite the complexity, **all server-internal communication uses `localhost`**, making configuration straightforward once you understand the pattern.

---

**Generated**: 2025-11-06
**Version**: 1.0
**Architecture**: HWC Charter v6.0
**Machine**: hwc-server
**Author**: Claude Code (AI Assistant)
