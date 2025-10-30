# Charter Migration Guide: Monolith to Modular Containers

**Purpose**: Guide for migrating monolithic container configurations to Charter-compliant domain modules

**Context**: Migration from `/etc/nixos/hosts/server/modules/media-containers.nix` (714 lines) to `domains/server/containers/` structure

---

## Overview

This guide demonstrates how to extract individual container definitions from a monolithic configuration file and implement them as Charter-compliant modules following the Unit Anatomy pattern.

### Charter Requirements

Each container module must follow:
- **Namespace**: `hwc.services.containers.SERVICE`
- **Unit Anatomy**: `options.nix`, `index.nix`, `parts/config.nix`, `sys.nix`
- **Secrets**: agenix integration (not SOPS)
- **Validation**: Proper assertions for dependencies
- **Lane Purity**: System lane only, no Home Manager violations

---

## Step-by-Step Migration Process

### 1. Analyze Monolith Container Definition

**Source Location**: `/etc/nixos/hosts/server/modules/media-containers.nix`

Extract the target container's configuration block:
```nix
# Example: gluetun VPN container
gluetun = {
  image = "qmcgaw/gluetun:latest";
  autoStart = true;
  extraOptions = [
    "--cap-add=NET_ADMIN"
    "--device=/dev/net/tun:/dev/net/tun"
    "--network=${mediaNetworkName}"
    "--network-alias=gluetun"
  ];
  ports = [
    "127.0.0.1:8080:8080"  # qBittorrent UI
    "127.0.0.1:8081:8085"  # SABnzbd
  ];
  volumes = [ "${cfgRoot}/gluetun:/gluetun" ];
  environmentFiles = [ "${cfgRoot}/.env" ];
  environment = { TZ = config.time.timeZone or "America/Denver"; };
};
```

**Identify Dependencies**:
- Secrets (VPN credentials)
- Network setup (media-network)
- Environment file generation
- Volume mounts
- Service ordering

### 2. Create Charter Module Structure

**Target Location**: `domains/server/containers/SERVICE/`

The Charter structure already exists but needs implementation:
```
domains/server/containers/gluetun/
├── index.nix        # Main aggregator
├── options.nix      # API definition
├── parts/
│   ├── config.nix   # Implementation details
│   ├── lib.nix      # Helper functions
│   ├── pkgs.nix     # Package definitions
│   └── scripts.nix  # Script helpers
└── sys.nix          # System-lane support
```

### 3. Implement Options Definition

**File**: `domains/server/containers/SERVICE/options.nix`

```nix
# Example: gluetun options
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.gluetun = {
    enable = mkEnableOption "gluetun VPN container";
    image = mkOption {
      type = types.str;
      default = "qmcgaw/gluetun:latest";
      description = "Container image";
    };
    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "media";
    };
    gpu.enable = mkOption {
      type = types.bool;
      default = true;
    };
  };
}
```

### 4. Implement Main Module

**File**: `domains/server/containers/SERVICE/index.nix`

```nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.gluetun;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./sys.nix
    ./parts/config.nix
    ./parts/scripts.nix
    ./parts/pkgs.nix
    ./parts/lib.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # VPN secrets are declared in domains/secrets/declarations/infrastructure.nix
    # Accessible via config.age.secrets.vpn-username.path and config.age.secrets.vpn-password.path

    # Validation assertions
    assertions = [
      {
        assertion = config.hwc.secrets.enable;
        message = "Gluetun requires hwc.secrets.enable = true for VPN credentials";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "Gluetun requires Podman as OCI container backend";
      }
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Validation logic above within config block
}
```

### 5. Implement Container Configuration

**File**: `domains/server/containers/SERVICE/parts/config.nix`

```nix
# gluetun container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.gluetun;
  cfgRoot = "/opt/downloads";
  mediaNetworkName = "media-network";
in
{
  config = lib.mkIf cfg.enable {
    # Gluetun environment file setup from agenix secrets
    systemd.services.gluetun-env-setup = {
      description = "Generate Gluetun env from agenix secrets";
      before   = [ "podman-gluetun.service" ];
      wantedBy = [ "podman-gluetun.service" ];
      wants    = [ "agenix.service" ];
      after    = [ "agenix.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p ${cfgRoot}
        VPN_USERNAME=$(cat ${config.age.secrets.vpn-username.path})
        VPN_PASSWORD=$(cat ${config.age.secrets.vpn-password.path})
        cat > ${cfgRoot}/.env <<EOF
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=$VPN_USERNAME
OPENVPN_PASSWORD=$VPN_PASSWORD
SERVER_COUNTRIES=Netherlands
HEALTH_VPN_DURATION_INITIAL=30s
EOF
        chmod 600 ${cfgRoot}/.env
        chown root:root ${cfgRoot}/.env
      '';
    };

    # Container definition
    virtualisation.oci-containers.containers.gluetun = {
      image = cfg.image;
      autoStart = true;
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--device=/dev/net/tun:/dev/net/tun"
        "--network=${mediaNetworkName}"
        "--network-alias=gluetun"
      ];
      ports = [
        "127.0.0.1:8080:8080"  # qBittorrent UI
        "127.0.0.1:8081:8085"  # SABnzbd (container uses 8085 internally)
      ];
      volumes = [ "${cfgRoot}/gluetun:/gluetun" ];
      environmentFiles = [ "${cfgRoot}/.env" ];
      environment = {
        TZ = config.time.timeZone or "America/Denver";
      };
    };

    # Service dependencies
    systemd.services."podman-gluetun".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-gluetun".wants = [ "network-online.target" ];
  };
}
```

### 6. Handle System Lane

**File**: `domains/server/containers/SERVICE/sys.nix`

```nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.gluetun;
in
{
  config = lib.mkIf cfg.enable {
    # System-lane support - actual container definition is in parts/config.nix
    # to avoid conflicts with the detailed implementation
    virtualisation.oci-containers.backend = "podman";
  };
}
```

### 7. Handle Secrets Migration

**Critical**: Charter uses agenix, not SOPS

**OLD (Monolith)**:
```nix
sops.secrets.vpn_username = {
  sopsFile = ../../../secrets/admin.yaml;
  key = "vpn/protonvpn/username";
  mode = "0400"; owner = "root"; group = "root";
};
```

**NEW (Charter)**:
Secrets are declared in `domains/secrets/declarations/infrastructure.nix`:
```nix
age.secrets = {
  vpn-username = {
    file = ../parts/infrastructure/vpn-username.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };
};
```

Access via: `config.age.secrets.vpn-username.path`

### 8. Enable Container in Profile

**File**: `profiles/server.nix`

```nix
imports = [
  ../domains/infrastructure/index.nix
  # Container services (Charter v6 migration in progress)
  ../domains/server/containers/index.nix
];

# Container services (Charter v6 migration test)
hwc.services.containers.gluetun.enable = true;
```

### 9. Test and Validate

```bash
# Test build
sudo nixos-rebuild build --flake .#hwc-server

# Compare configurations
sudo python3 workspace/utilities/config-validation/system-distiller.py > /tmp/old-system.json
sudo python3 workspace/utilities/config-validation/system-distiller.py > /tmp/new-system.json

# Look for differences
bash workspace/utilities/config-validation/config-differ.sh /tmp/old-system.json /tmp/new-system.json
```

---

## Common Patterns and Gotchas

### 1. Container Builder Functions

**Monolith Pattern**:
```nix
buildMediaServiceContainer = { name, image, mediaType, extraVolumes ? [], ... }:
```

**Charter Pattern**: Extract to individual modules with clear configuration

### 2. Network Dependencies

**Required**: Ensure media network creation service is imported via `_shared/network.nix`

### 3. Volume Mount Preservation

**Critical Mounts to Preserve**:
- `/mnt/hot/events:/mnt/hot/events` (SABnzbd event processing)
- `/opt/downloads/scripts:/config/scripts:ro` (Script access)
- Config directories: `/opt/downloads/SERVICE:/config`

### 4. Service Ordering

**Pattern**:
```nix
systemd.services."podman-SERVICE".after = [ "init-media-network.service" ];
systemd.services."podman-SERVICE".wants = [ "network-online.target" ];
```

### 5. Environment Variable Conflicts

**Issue**: Multiple files defining same container environment variables
**Solution**: Consolidate in `parts/config.nix`, disable conflicting definitions in `sys.nix`

---

## Validation Checklist

- [ ] **Build succeeds**: `sudo nixos-rebuild build --flake .#hwc-server`
- [ ] **Namespace correct**: `hwc.services.containers.SERVICE`
- [ ] **Secrets working**: agenix paths accessible
- [ ] **No conflicts**: Single container definition per service
- [ ] **Dependencies preserved**: Network, storage, ordering
- [ ] **Charter compliance**: Unit Anatomy followed

---

## Migration Order Recommendation

1. **Foundation**: gluetun (VPN base) ✅ Complete
2. **Downloads**: qbittorrent, sabnzbd
3. **Indexing**: prowlarr
4. **Media Management**: sonarr, radarr, lidarr
5. **Specialized**: soularr, navidrome
6. **Infrastructure**: caddy (reverse proxy)

Each subsequent container follows this same pattern, building on the established foundation.