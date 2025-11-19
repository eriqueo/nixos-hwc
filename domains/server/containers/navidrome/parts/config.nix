# Navidrome container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.navidrome;
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
        message = "Navidrome with VPN networking requires gluetun container to be enabled";
      }
      {
        assertion = paths.media != null;
        message = "Navidrome requires hwc.paths.media to be configured for music library";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.navidrome = {
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
        ND_BASEURL = "/music";  # Required for Caddy subpath routing
      };

      # Port exposure - bind to localhost (Caddy will proxy)
      ports = [ "127.0.0.1:4533:4533" ];

      # Volume mounts
      volumes = [
        "/opt/downloads/navidrome:/config"
        "${paths.media}/music:/music:ro"
      ];

      # Dependencies
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-navidrome = {
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
