{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.qbittorrent;
  paths = config.hwc.paths;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.services.containers.gluetun.enable;
        message = "qBittorrent with VPN networking requires gluetun container to be enabled";
      }
      {
        assertion = paths.hot != null;
        message = "qBittorrent requires hwc.paths.hot to be configured for downloads";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.qbittorrent = {
      image = cfg.image;
      autoStart = true;

      # Network configuration - use gluetun network namespace for VPN mode
      extraOptions = [
        "--memory=2g"
        "--cpus=1.0"
        "--memory-swap=4g"
      ] ++ (
        if cfg.network.mode == "vpn"
        then [ "--network=container:gluetun" ]
        else [ "--network=media-network" ]
      ) ++ lib.optionals cfg.gpu.enable [
        "--device=/dev/dri:/dev/dri"
      ];

      # Environment variables
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone or "America/Denver";
        WEBUI_PORT = toString cfg.webPort;
      };

      # Port exposure - only when not using VPN (gluetun exposes ports)
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "${toString cfg.webPort}:${toString cfg.webPort}"
      ];

      # Volume mounts
      volumes = [
        "${paths.hot}/downloads/qbittorrent:/config"
        "${paths.hot}/downloads:/downloads"
      ];

      # Dependencies
      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-qbittorrent = {
      after = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "hwc-media-network.service" ];
      wants = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "hwc-media-network.service" ];
    };

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    networking.firewall.allowedTCPPorts = lib.optionals (cfg.network.mode != "vpn") [
      cfg.webPort
    ];
  };
}
