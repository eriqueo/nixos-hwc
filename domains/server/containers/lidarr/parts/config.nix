# Lidarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.lidarr;
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
        message = "Lidarr with VPN networking requires gluetun container to be enabled";
      }
      {
        assertion = paths.media != null;
        message = "Lidarr requires hwc.paths.media to be configured for music library";
      }
      {
        assertion = paths.hot != null;
        message = "Lidarr requires hwc.paths.hot to be configured for downloads";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.lidarr = {
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
        LIDARR__URLBASE = "/lidarr";  # Required for Caddy subpath routing
      };

      # Port exposure - bind to localhost (Caddy will proxy)
      ports = [ "127.0.0.1:8686:8686" ];

      # Volume mounts
      volumes = [
        "/opt/downloads/lidarr:/config"
        "${paths.media}/music:/music"
        "${paths.hot}/downloads:/downloads"
      ];

      # Dependencies - Prowlarr for indexers, or Gluetun for VPN mode
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-lidarr = {
      after = [
        "network-online.target"
        "agenix.service"
      ] ++ (
        if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "init-media-network.service" ]
      );

      wants = [
        "network-online.target"
        "agenix.service"
      ] ++ (
        if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "init-media-network.service" ]
      );
    };
  };
}
