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
    , vpnContainer ? "gluetun"  # which tunnel instance "vpn" mode joins
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
    , pull ? "missing"          # "always" | "missing" | "never" | "newer"
    }:
    let
      # Network options.
      #
      # "vpn" resolves ONLY to a tunnel netns — there is deliberately no fallback
      # branch here. slskd spent six weeks egressing on the house IP because its
      # network mode said "media" and nothing objected; a container that asks for
      # the tunnel and quietly gets the bridge instead is the same failure with a
      # different spelling. A wrong vpnContainer name must break the container,
      # not silently un-tunnel it. Enforcement that the named instance is real
      # and enabled lives in mkVpnAssertions below, which every VPN-mode module
      # calls.
      podmanNetworkOpts =
        if networkMode == "vpn" then [ "--network=container:${vpnContainer}" ]
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
        inherit image dependsOn pull;
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

  # Assertions every VPN-mode container needs, produced in one place.
  #
  # These used to be hand-copied into eight modules as
  # `cfg.network.mode != "vpn" || config.hwc.networking.gluetun.enable` — same
  # predicate, eight spellings, and all eight only checked that *a* tunnel
  # existed, not that the one this container joins does. With more than one
  # tunnel that check is worse than none: a container can name a tunnel that was
  # never declared and still pass. Callers pass the live instance set:
  #
  #   mkVpnAssertions {
  #     name = "slskd"; networkMode = cfg.network.mode;
  #     vpnContainer = "gluetun-slskd";
  #     gluetunInstances = config.hwc.networking.gluetun.instances;
  #   }
  mkVpnAssertions =
    { name
    , networkMode
    , vpnContainer ? "gluetun"
    , gluetunInstances
    }:
    lib.optionals (networkMode == "vpn") [
      {
        assertion = gluetunInstances ? ${vpnContainer};
        message = "${name} requests VPN networking on tunnel '${vpnContainer}', which is not declared in hwc.networking.gluetun.instances";
      }
      {
        assertion = lib.attrByPath [ vpnContainer "enable" ] false gluetunInstances;
        message = "${name} requests VPN networking on tunnel '${vpnContainer}', which is declared but not enabled";
      }
    ];
}
