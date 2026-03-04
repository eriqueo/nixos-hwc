{ lib, config, pkgs, ... }:
let
  # Import PURE helper library
  helpers = import ../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;

  cfg = config.hwc.server.containers.qbittorrent;
  paths = config.hwc.paths;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/qbittorrent/config";
  qbtConfigDir = "${configPath}/qBittorrent";

  # Generate categories.json content from Nix options
  categoriesJson = builtins.toJSON (
    lib.mapAttrs (name: cat: { save_path = cat.savePath; }) cfg.categories
  );

  # Script to enforce categories.json before container starts
  enforceCategoriesScript = pkgs.writeShellScript "qbittorrent-enforce-categories" ''
    set -euo pipefail

    mkdir -p "${qbtConfigDir}"

    cat > "${qbtConfigDir}/categories.json" << 'EOF'
${categoriesJson}
EOF

    chown -R 1000:100 "${qbtConfigDir}/categories.json"
  '';
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    {
      assertions = [
        {
          assertion = cfg.network.mode != "vpn" || config.hwc.server.containers.gluetun.enable;
          message = "qBittorrent with VPN networking requires gluetun container to be enabled";
        }
        {
          assertion = paths.hot != null;
          message = "qBittorrent requires hwc.paths.hot to be configured for downloads";
        }
      ];
    }

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    (mkContainer {
      name = "qbittorrent";
      image = cfg.image;
      networkMode = if cfg.network.mode == "vpn" then "vpn" else "media";
      gpuEnable = cfg.gpu.enable;
      timeZone = config.time.timeZone or "America/Denver";

      environment = {
        WEBUI_PORT = toString cfg.webPort;
      };

      # Port exposure - only when not using VPN (gluetun exposes ports)
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "127.0.0.1:${toString cfg.webPort}:${toString cfg.webPort}"
      ];

      volumes = [
        "${configPath}:/config"
        "${paths.hot.root}/downloads:/downloads"
        "${config.hwc.paths.hot.downloads}/scripts:/scripts:ro"
        "${paths.hot.root}/events:/mnt/hot/events"
      ];

      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    })

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    {
      systemd.services.podman-qbittorrent = {
        serviceConfig.ExecStartPre = [
          "+${enforceCategoriesScript}"  # + prefix runs as root
        ];
        after = if cfg.network.mode == "vpn"
          then [ "podman-gluetun.service" "mnt-hot.mount" ]
          else [ "hwc-media-network.service" "mnt-hot.mount" ];
        wants = if cfg.network.mode == "vpn"
          then [ "podman-gluetun.service" ]
          else [ "hwc-media-network.service" ];
        requires = [ "mnt-hot.mount" ];
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
