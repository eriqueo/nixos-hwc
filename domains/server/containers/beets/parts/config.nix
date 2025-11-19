# Beets container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.beets;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.services.containers.gluetun.enable;
        message = "Beets with VPN networking requires gluetun container to be enabled";
      }
      {
        assertion = cfg.configDir != null && cfg.musicDir != null && cfg.importDir != null;
        message = "Beets requires configDir, musicDir, and importDir to be configured";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.beets = {
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
      );

      # Environment variables
      environment = {
        PUID = "1000";
        PGID = "100";
        TZ = config.time.timeZone or "America/Denver";
      };

      # Port exposure - bind to localhost (Caddy will proxy)
      ports = [ "127.0.0.1:8337:8337" ];

      # Volume mounts
      volumes = [
        "${cfg.configDir}:/config"
        "${cfg.musicDir}:/music"
        "${cfg.importDir}:/imports"
        "/mnt/media/quarantine:/quarantine"
      ];

      # Dependencies
      dependsOn = [ ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-beets = {
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
