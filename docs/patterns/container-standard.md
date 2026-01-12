# Container Standard and mkContainer Helper

**Source**: Extracted from Charter v8.0 Section 16 + mkContainer implementation
**Related**: Charter v9.0 Section 2 (Server Domain - mkContainer Pattern)
**Implementation**: `domains/server/containers/_shared/pure.nix`

## Overview

The HWC container standard uses the `mkContainer` helper to reduce boilerplate and enforce consistent patterns across all OCI containers. Raw `virtualisation.oci-containers.containers` definitions are discouraged.

**Boilerplate Reduction**: ~50 lines of manual container config → ~18 lines with mkContainer

---

## Container vs Native Service Decision Matrix

Choose between containerized and native services based on connectivity requirements:

### Use Native Services For:

✅ **External device connectivity** (media servers, game servers)
- Media services requiring LAN device access (Jellyfin for Roku/smart TVs)
- Services with complex network discovery requirements (mDNS, UPnP)
- Services accessed by devices that can't reach Docker networks

**Example**: Jellyfin (native)
```nix
# Native service for LAN device access
services.jellyfin.enable = true;
# NOT: hwc.server.containers.jellyfin.enable
```

**Why**: Container networks create routing barriers. External devices (Roku, smart TVs, game consoles) may not reach containerized services despite proper port mapping.

### Use Containers For:

✅ **Internal services and isolated workloads**
- API services, databases, processing workloads
- Services without external device connectivity requirements
- Better security isolation for untrusted workloads
- Services accessed only via web browser or internal apps

**Examples**: Radarr, Sonarr, qBittorrent, databases, API servers

---

## The mkContainer Helper

### Location

`domains/server/containers/_shared/pure.nix`

### Function Signature

```nix
mkContainer =
  { name            # Container name (required)
  , image           # Container image (required)
  , networkMode ? "media"         # "media" or "vpn" (via gluetun)
  , gpuEnable ? true              # Enable GPU passthrough
  , gpuMode ? "intel"             # GPU type (intel/nvidia/amd)
  , timeZone ? "UTC"              # Container timezone
  , ports ? []                    # Port mappings
  , volumes ? []                  # Volume mounts
  , environment ? {}              # Additional env vars
  , extraOptions ? []             # Extra podman options
  , dependsOn ? []                # Container dependencies
  , user ? null                   # Override user (default: 1000:100)
  , cmd ? []                      # Override container command
  }:
```

### Automatic Behavior

The mkContainer helper **automatically** provides:

1. **Standard Environment**:
   ```nix
   {
     PUID = "1000";  # Primary user (Law 4)
     PGID = "100";   # users group (Law 4)
     TZ = timeZone;  # Timezone from parameter
   }
   ```

2. **Network Configuration**:
   - `networkMode = "media"` → `--network=media-network`
   - `networkMode = "vpn"` → `--network=container:gluetun`

3. **GPU Passthrough** (when enabled):
   ```nix
   --device=/dev/dri:/dev/dri  # Intel/AMD GPU
   ```

4. **Resource Limits**:
   ```nix
   --memory=2g
   --cpus=1.0
   --memory-swap=4g
   ```

5. **Auto-start**: `autoStart = true`

---

## Usage Examples

### Basic Container

```nix
# domains/server/containers/radarr/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.containers.radarr;
  mkContainer = (import ../_shared/pure.nix { inherit lib pkgs; }).mkContainer;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable (mkContainer {
    name = "radarr";
    image = "lscr.io/linuxserver/radarr:5.14.0";

    volumes = [
      "/opt/radarr:/config"
      "${config.hwc.paths.media.movies}:/movies"
      "${config.hwc.paths.hot.downloads.root}:/downloads"
    ];

    ports = [ "7878:7878" ];
  });
}
```

**Result**: Full container definition in ~15 lines instead of ~50 lines of boilerplate.

### VPN-Routed Container

For services that must route through VPN (torrents, usenet):

```nix
config = lib.mkIf cfg.enable (mkContainer {
  name = "qbittorrent";
  image = "lscr.io/linuxserver/qbittorrent:4.6.7";

  networkMode = "vpn";  # Route through gluetun container

  volumes = [
    "/opt/qbittorrent:/config"
    "${config.hwc.paths.hot.downloads.torrents}:/downloads"
  ];

  ports = [];  # Ports exposed via gluetun
  dependsOn = [ "gluetun" ];
});
```

### Container Without GPU

For services that don't need GPU access:

```nix
config = lib.mkIf cfg.enable (mkContainer {
  name = "pihole";
  image = "pihole/pihole:2024.07.0";

  gpuEnable = false;  # No GPU needed

  volumes = [
    "/opt/pihole/etc-pihole:/etc/pihole"
    "/opt/pihole/etc-dnsmasq.d:/etc/dnsmasq.d"
  ];

  ports = [
    "53:53/tcp"
    "53:53/udp"
    "8053:80/tcp"
  ];

  environment = {
    WEBPASSWORD = "admin";
  };
});
```

### Container with Custom Environment

```nix
config = lib.mkIf cfg.enable (mkContainer {
  name = "immich";
  image = "ghcr.io/immich-app/immich-server:v1.122.3";

  volumes = [
    "/opt/immich:/usr/src/app/upload"
    "${config.hwc.paths.photos}:/photos:ro"
  ];

  ports = [ "2283:2283" ];

  environment = {
    # Additional env vars merged with base (PUID, PGID, TZ)
    DB_HOSTNAME = "postgres";
    DB_DATABASE_NAME = "immich";
    DB_USERNAME = "immich";
    REDIS_HOSTNAME = "redis";
  };

  dependsOn = [ "postgres" "redis" ];
});
```

---

## Container Architecture Rules

### 1. Network Isolation

**Rule**: Container networks create routing barriers.

- **media-network**: Default network for internal services
- **vpn**: Route through gluetun for torrents/usenet
- **External devices**: May not reach containers despite port mapping

**Implication**: Services accessed by LAN devices (Rokus, smart TVs) should be native, not containerized.

### 2. Reverse Proxy Authority

**Rule**: Reverse proxy authority is central in `domains/server/containers/caddy/`.

- When host-level Caddy aggregator is enabled, containerized proxy units MUST be disabled
- One source of truth for routing
- Avoid multiple reverse proxies competing

### 3. State Directory Defaults

**Rule**: Container state defaults to `/opt/<category>/<unit>:/config`

**Standard Pattern**:
```nix
volumes = [
  "/opt/radarr:/config"  # Persistent container state
  # ... data volumes
];
```

**Override only for**:
- Ephemeral workloads (no persistent state)
- Host storage policy requirements
- Multiple instances of same service

### 4. Permission Standard (Law 4)

**Rule**: All containers use PUID=1000, PGID=100 (automatically set by mkContainer)

```nix
# Automatically set by mkContainer
environment = {
  PUID = "1000";  # eric user
  PGID = "100";   # users group (NOT 1000!)
  TZ = timeZone;
};
```

**Why PGID=100**: Ensures container-created files are owned by `eric:users`, allowing direct host access without permission corrections.

---

## Anti-Patterns

### ❌ Raw Container Definitions

**DON'T DO THIS**:
```nix
# 50+ lines of boilerplate
virtualisation.oci-containers.containers.radarr = {
  image = "lscr.io/linuxserver/radarr:5.14.0";
  autoStart = true;
  environment = {
    PUID = "1000";
    PGID = "100";
    TZ = "America/Denver";
  };
  extraOptions = [
    "--network=media-network"
    "--device=/dev/dri:/dev/dri"
    "--memory=2g"
    "--cpus=1.0"
    "--memory-swap=4g"
  ];
  volumes = [
    "/opt/radarr:/config"
    "/mnt/media/movies:/movies"  # Hardcoded path!
    "/mnt/hot/downloads:/downloads"
  ];
  ports = [ "7878:7878" ];
};
```

**DO THIS INSTEAD**:
```nix
# 15 lines with mkContainer
mkContainer {
  name = "radarr";
  image = "lscr.io/linuxserver/radarr:5.14.0";
  volumes = [
    "/opt/radarr:/config"
    "${config.hwc.paths.media.movies}:/movies"  # Path abstraction (Law 3)
    "${config.hwc.paths.hot.downloads.root}:/downloads"
  ];
  ports = [ "7878:7878" ];
}
```

### ❌ Wrong PGID

**DON'T DO THIS**:
```nix
environment = {
  PUID = "1000";
  PGID = "1000";  # WRONG! Should be 100
};
```

**Result**: Files owned by `eric:eric` instead of `eric:users`, breaking shared access patterns.

### ❌ Containerizing Services with External Device Access

**DON'T DO THIS**:
```nix
# Jellyfin in container - Roku can't reach it
hwc.server.containers.jellyfin.enable = true;
```

**DO THIS INSTEAD**:
```nix
# Jellyfin as native service - Roku can reach it
services.jellyfin.enable = true;
```

---

## Migration from Raw Containers

When migrating existing raw container definitions to mkContainer:

### Step 1: Identify Current Config

```nix
# OLD: Raw definition
virtualisation.oci-containers.containers.myservice = {
  image = "...";
  environment = { PUID = "1000"; PGID = "100"; TZ = "..."; };
  volumes = [ ... ];
  ports = [ ... ];
  extraOptions = [ "--network=media-network" "--device=/dev/dri:/dev/dri" ];
};
```

### Step 2: Extract to mkContainer

```nix
# NEW: Using mkContainer
let
  mkContainer = (import ../_shared/pure.nix { inherit lib pkgs; }).mkContainer;
in
  mkContainer {
    name = "myservice";
    image = "...";
    volumes = [ ... ];  # Same volumes
    ports = [ ... ];    # Same ports
    # PUID/PGID/TZ/network/GPU automatically handled
  }
```

### Step 3: Remove Redundant Options

mkContainer automatically provides:
- ✂️ Remove `PUID`, `PGID`, `TZ` from environment
- ✂️ Remove `--network=media-network` from extraOptions
- ✂️ Remove `--device=/dev/dri:/dev/dri` from extraOptions (if gpuEnable=true)
- ✂️ Remove `autoStart = true`

### Step 4: Verify & Deploy

```bash
# Test build
sudo nixos-rebuild test --flake .#hwc-server

# Verify container running
podman ps | grep myservice

# Check permissions on container-created files
ls -la /path/to/container/data
# Should show: eric:users (UID 1000, GID 100)
```

---

## Benefits

| Aspect | Raw Container | mkContainer |
|--------|---------------|-------------|
| **Lines of code** | ~50 lines | ~15 lines |
| **Boilerplate** | Manual | Automatic |
| **Permission standard** | Manual (error-prone) | Enforced (PUID/PGID) |
| **Network config** | Manual | Automatic (media/vpn) |
| **GPU passthrough** | Manual | Automatic (when enabled) |
| **Consistency** | Varies per module | Uniform across repo |
| **Maintenance** | Update each container | Update helper once |

---

## Advanced: Custom Networks

For special networking requirements, use `extraOptions`:

```nix
mkContainer {
  name = "custom-network-service";
  image = "...";
  networkMode = "media";  # Still use helper for base network
  extraOptions = [
    "--ip=192.168.1.50"  # Static IP in media network
  ];
}
```

---

## See Also

- **Charter v9.0 Law 4**: Permission Standard (1000:100)
- **Charter v9.0 Law 3**: Path Abstraction Contract
- **Charter v9.0 Section 2**: Server Domain Overview (mkContainer Pattern)
- **domains/server/README.md**: Server workload patterns
- **domains/server/containers/_shared/pure.nix**: mkContainer implementation
- **docs/patterns/config-first-services.md**: Complex service configuration pattern
