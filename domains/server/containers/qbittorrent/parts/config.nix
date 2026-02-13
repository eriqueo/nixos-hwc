{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.qbittorrent;
  paths = config.hwc.paths;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/qbittorrent/config";
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
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
        PUID = "1000";  # eric UID
        PGID = "100";   # users GID (CRITICAL - users group is GID 100, not 1000!)
        TZ = config.time.timeZone or "America/Denver";
        WEBUI_PORT = toString cfg.webPort;
      };

      # Port exposure - only when not using VPN (gluetun exposes ports)
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "127.0.0.1:${toString cfg.webPort}:${toString cfg.webPort}"
      ];

      # Volume mounts
      volumes = [
        "${configPath}:/config"
        "${paths.hot.root}/downloads:/downloads"
        "${config.hwc.paths.hot.downloads}/scripts:/scripts:ro"
        "${paths.hot.root}/events:/mnt/hot/events"
      ];

      # Dependencies
      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-qbittorrent = {
      after = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" "mnt-hot.mount" ]
        else [ "hwc-media-network.service" "mnt-hot.mount" ];
      wants = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "hwc-media-network.service" ];
      requires = [ "mnt-hot.mount" ];
    };

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    networking.firewall.allowedTCPPorts = lib.optionals (cfg.network.mode != "vpn") [
      cfg.webPort
    ];
  };
}
