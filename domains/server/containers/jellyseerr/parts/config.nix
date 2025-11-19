# Jellyseerr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.jellyseerr;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.services.containers.gluetun.enable;
        message = "Jellyseerr with VPN networking requires gluetun container to be enabled";
      }
      {
        assertion = config.hwc.services.containers.sonarr.enable || config.hwc.services.containers.radarr.enable;
        message = "Jellyseerr requires at least Sonarr or Radarr to be enabled";
      }
    ];

    #=========================================================================
    # SYSTEMD TMPFILES
    #=========================================================================
    systemd.tmpfiles.rules = [
      "d /opt 0755 root root -"
      "d /opt/jellyseerr 0755 1000 1000 -"
      "d /opt/jellyseerr/config 0755 1000 1000 -"
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.jellyseerr = {
      image = cfg.image;
      autoStart = true;
      user = "1000:1000";

      # Network configuration
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
      };

      # Port exposure - bind to localhost (Caddy will proxy)
      ports = [ "127.0.0.1:5055:5055" ];

      # Volume mounts
      volumes = [
        "/opt/jellyseerr/config:/app/config:rw"
      ];

      # Dependencies - needs Sonarr and Radarr for requests
      dependsOn = [ "sonarr" "radarr" ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-jellyseerr = {
      after = [
        "network-online.target"
        "podman-sonarr.service"
        "podman-radarr.service"
      ] ++ (
        if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "init-media-network.service" ]
      );

      wants = [
        "network-online.target"
      ] ++ (
        if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "init-media-network.service" ]
      );
    };
  };
}
