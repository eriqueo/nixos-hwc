# Jellyfin container configuration (alternative to native service)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.jellyfin;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.services.containers.gluetun.enable;
        message = "Jellyfin with VPN networking requires gluetun container to be enabled";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.jellyfin = {
      image = cfg.image;
      autoStart = true;

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

      # Port exposure - Jellyfin uses 0.0.0.0 for LAN discovery
      ports = [ "0.0.0.0:8096:8096" ];

      # Volume mounts
      volumes = [
        "/opt/downloads/jellyfin:/config"
      ];

      # Dependencies
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-jellyfin = {
      after = [
        "network-online.target"
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
