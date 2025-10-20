{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.sabnzbd;
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
        message = "SABnzbd with VPN networking requires gluetun container to be enabled";
      }
      {
        assertion = paths.hot != null;
        message = "SABnzbd requires hwc.paths.hot to be configured for downloads and events";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.sabnzbd = {
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
      } // lib.optionalAttrs (cfg.network.mode == "vpn") {
        # When using VPN, SABnzbd runs on port 8085 inside container
        # but gluetun exposes it as 8081 externally
        SABNZBD_PORT = "8085";
      } // lib.optionalAttrs (cfg.network.mode != "vpn") {
        # When not using VPN, use the configured webPort directly
        SABNZBD_PORT = toString cfg.webPort;
      };

      # Port exposure - only when not using VPN (gluetun exposes ports)
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "${toString cfg.webPort}:${toString cfg.webPort}"
      ];

      # Volume mounts - CRITICAL: events mount is required for automation pipeline
      volumes = [
        "/opt/downloads/sabnzbd:/config"
        "${paths.hot}/downloads:/downloads"
        "${paths.hot}/events:/mnt/hot/events"  # CRITICAL for event processing
        "/opt/downloads/scripts:/config/scripts:ro"  # Post-processing scripts
      ];

      # Dependencies
      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-sabnzbd = {
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
