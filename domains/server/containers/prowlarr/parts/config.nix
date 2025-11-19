# Prowlarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.prowlarr;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.services.containers.gluetun.enable;
        message = "Prowlarr with VPN networking requires gluetun container to be enabled";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.prowlarr = {
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
        PROWLARR__URLBASE = "/prowlarr";  # Required for Caddy subpath routing
      };

      # Port exposure - bind to localhost (Caddy will proxy)
      ports = [ "127.0.0.1:9696:9696" ];

      # Volume mounts
      volumes = [
        "/opt/downloads/prowlarr:/config"
      ];

      # Dependencies - Independent indexer manager, or Gluetun for VPN mode
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-prowlarr = {
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
