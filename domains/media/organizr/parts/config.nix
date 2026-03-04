# Organizr container configuration
{ lib, config, pkgs, ... }:
let
  # Import PURE helper library
  helpers = import ../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;

  cfg = config.hwc.server.containers.organizr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/organizr/config";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    {
      assertions = [
        {
          assertion = config.hwc.networking.reverseProxy.enable;
          message = "Organizr works best with reverse proxy enabled for service integration";
        }
      ];
    }

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    (mkContainer {
      name = "organizr";
      image = cfg.image;
      networkMode = if cfg.network.mode == "vpn" then "vpn" else "media";
      gpuEnable = cfg.gpu.enable;
      timeZone = config.time.timeZone or "America/Denver";

      # Resource limits (lighter than default)
      memory = "1g";
      cpus = "0.5";
      memorySwap = "2g";

      environment = {
        branch = "v2-master";  # v2-master is stable
      };

      # Port exposure (80 is container internal port)
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "127.0.0.1:${toString cfg.webPort}:80"
      ];

      volumes = [
        "${configPath}:/config"
      ];

      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    })

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    {
      systemd.services.podman-organizr = {
        after = if cfg.network.mode == "vpn"
          then [ "podman-gluetun.service" ]
          else [ "init-media-network.service" ];
        wants = if cfg.network.mode == "vpn"
          then [ "podman-gluetun.service" ]
          else [ "init-media-network.service" ];
      };
    }

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    {
      networking.firewall.allowedTCPPorts = lib.optionals (cfg.network.mode != "vpn") [
        cfg.webPort
      ];
    }
  ]);
}
