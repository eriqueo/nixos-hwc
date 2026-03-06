# Application Container Helper
# For standard application containers (media apps, *arr services)
# See mkInfraContainer.nix for infrastructure containers (gluetun, pihole)
#
# =============================================================================
# CONTAINER MODULE STRUCTURE
# =============================================================================
#
# Standard directory layout for container modules:
#
#   domains/media/<app>/
#   ├── index.nix       # Main module: imports, mkIf wrapper, container definition
#   ├── options.nix     # Option declarations (hwc.media.<app>.*)
#   └── parts/          # Optional: max 2 files for complex configs
#       ├── config.nix  # INSIDE: app config generation (YAML/TOML/JSON, templates)
#       └── setup.nix   # OUTSIDE: runtime setup (systemd deps, tmpfiles, firewall)
#
# Guidelines:
#   - Container definition stays in index.nix (it's the main thing the module does)
#   - Use parts/ only when index.nix gets too long (>50 lines of config)
#   - config.nix = what the app needs to know about itself
#   - setup.nix = what NixOS needs to run the app (pre-start, deps, networking)
#   - Multiple home.file or environment.etc entries can live in one parts file
#
# =============================================================================
{ lib, pkgs }:

rec {
  mkContainer =
    { name
    , image
    , networkMode ? "media"     # "media" | "vpn" | "host"
    , gpuEnable ? true
    , gpuMode ? "intel"         # "intel" | "nvidia-cdi" | "nvidia-legacy"
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
    }:
    let
      # Network options
      podmanNetworkOpts =
        if networkMode == "vpn" then [ "--network=container:gluetun" ]
        else if networkMode == "host" then [ "--network=host" ]
        else [ "--network=media-network" ];

      # GPU options based on mode
      gpuOpts =
        if (!gpuEnable) then []
        else if gpuMode == "nvidia-cdi" then [
          # NVIDIA CDI (Container Device Interface) mode - modern approach
          "--device=nvidia.com/gpu=0"
        ]
        else if gpuMode == "nvidia-legacy" then [
          # Legacy NVIDIA passthrough
          "--device=/dev/nvidia0:/dev/nvidia0:rwm"
          "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
          "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
          "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
          "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
          "--device=/dev/dri:/dev/dri:rwm"
        ]
        else [
          # Intel/AMD GPU passthrough (default)
          "--device=/dev/dri:/dev/dri"
        ];

      # Base environment (PUID/PGID for linuxserver.io style containers)
      baseEnv = {
        PUID = "1000";  # eric UID
        PGID = "100";   # users GID (CRITICAL - users group is GID 100, not 1000!)
        TZ = timeZone;
      };

      # Resource limits
      resourceOpts = [
        "--memory=${memory}"
        "--cpus=${cpus}"
        "--memory-swap=${memorySwap}"
      ];

      containerDef = {
        inherit image dependsOn;
        autoStart = true;
        environment = baseEnv // environment;
        environmentFiles = environmentFiles;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ resourceOpts ++ extraOptions;
        ports = ports;
        volumes = volumes;
      } // lib.optionalAttrs (user != null) { inherit user; }
        // lib.optionalAttrs (cmd != []) { inherit cmd; };

    in {
      virtualisation.oci-containers.containers.${name} = containerDef;
    };
}
