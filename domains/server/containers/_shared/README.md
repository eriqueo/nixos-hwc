# Container Shared Helpers

## Purpose

Provides reusable container helper functions for Law 5 compliance. All containers in the server domain MUST use these helpers instead of raw `virtualisation.oci-containers.containers` definitions.

## Boundaries

- **Pure functions only**: Helpers must not read from `config` directly
- **Container definitions only**: No systemd services, firewall rules, etc. (those go in container modules)
- **No infrastructure logic**: DNS, VPN routing, etc. belong in container-specific modules

## Structure

```
_shared/
├── README.md           # This file
├── pure.nix            # Re-exports lib/mkContainer.nix (backwards compat)
├── infra.nix           # Re-exports lib/mkInfraContainer.nix (backwards compat)
├── arr-config.nix      # Re-exports lib/arr-config.nix (backwards compat)
├── lib.nix             # Module-based helpers (routes accumulator)
├── network.nix         # Media network initialization service
├── directories.nix     # Shared directory structures
└── caddy.nix           # Reverse proxy route helpers
```

> **Note**: The pure helper functions (mkContainer, mkInfraContainer, mkArrConfigScript)
> have been extracted to `lib/` at the repo root. The files here are thin re-export
> wrappers for backwards compatibility. New code should import from `lib/` directly.

## Usage

### Application Containers (mkContainer)

For standard containers like Sonarr, Radarr, Jellyfin, etc.

```nix
{ lib, pkgs, ... }:
let
  helpers = import ../_shared/pure.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;
in
{
  config = lib.mkIf cfg.enable (mkContainer {
    name = "sonarr";
    image = cfg.image;
    networkMode = "media";     # "media" | "vpn" | "host"
    gpuEnable = false;
    timeZone = "America/Denver";
    ports = [ "127.0.0.1:8989:8989" ];
    volumes = [ "${configPath}:/config" ];
    environment = { };
  });
}
```

### Infrastructure Containers (mkInfraContainer)

For containers with special requirements (capabilities, devices, privileged mode).

```nix
{ lib, pkgs, ... }:
let
  infraHelpers = import ../_shared/infra.nix { inherit lib pkgs; };
  inherit (infraHelpers) mkInfraContainer;
in
{
  config = lib.mkIf cfg.enable (mkInfraContainer {
    name = "gluetun";
    image = cfg.image;
    networkMode = "media-network";
    networkAliases = [ "gluetun" ];
    capabilities = [ "NET_ADMIN" "SYS_MODULE" ];
    devices = [ "/dev/net/tun:/dev/net/tun" ];
    privileged = true;
    preStartScript = ''
      # Generate env file from secrets
    '';
    preStartDeps = [ "agenix.service" ];
    firewallTcp = [ 53 ];
    firewallUdp = [ 53 ];
  });
}
```

## API Reference

### mkContainer (pure.nix)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| name | string | required | Container name |
| image | string | required | OCI image |
| networkMode | "media" \| "vpn" \| "host" | "media" | Network mode |
| gpuEnable | bool | true | Enable GPU passthrough |
| gpuMode | "intel" \| "nvidia-cdi" \| "nvidia-legacy" | "intel" | GPU passthrough method |
| timeZone | string | "UTC" | Container timezone |
| ports | list | [] | Port mappings |
| volumes | list | [] | Volume mounts |
| environment | attrs | {} | Environment variables |
| environmentFiles | list | [] | Env files to load |
| extraOptions | list | [] | Extra podman options |
| dependsOn | list | [] | Container dependencies |
| user | string | null | User to run as |
| cmd | list | [] | Command override |
| memory | string | "2g" | Memory limit |
| cpus | string | "1.0" | CPU limit |
| memorySwap | string | "4g" | Swap limit |

### mkInfraContainer (infra.nix)

All parameters from mkContainer plus:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| networkAliases | list | [] | Network aliases |
| dnsServers | list | [] | DNS servers |
| capabilities | list | [] | Linux capabilities |
| devices | list | [] | Device mappings |
| privileged | bool | false | Privileged mode |
| preStartScript | string | null | Script before container |
| preStartDeps | list | [] | Deps for preStart service |
| postStartScript | string | null | Script after container |
| assertions | list | [] | NixOS assertions |
| firewallTcp | list | [] | TCP firewall ports |
| firewallUdp | list | [] | UDP firewall ports |
| systemdAfter | list | [] | Systemd after deps |
| systemdWants | list | [] | Systemd wants deps |
| systemdRequires | list | [] | Systemd requires deps |

## Changelog

- 2026-02-28: Initial creation with mkContainer and mkInfraContainer helpers for Law 5 compliance
- 2026-02-28: Updated pure.nix with nvidia-cdi GPU mode support
- 2026-02-28: Cleaned up lib.nix to remove duplicate mkContainer
- 2026-03-04: Extracted pure helpers to lib/ at repo root; pure.nix, infra.nix, arr-config.nix now re-export
