# Sonarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.sonarr;
  cfgRoot = "/opt/downloads";
  mediaNetworkName = "media-network";
in
{
  config = lib.mkIf cfg.enable {
    # Container definition
    virtualisation.oci-containers.containers.sonarr = {
      image = cfg.image;
      autoStart = true;
      extraOptions = [
        "--network=${mediaNetworkName}"
        "--memory=2g"
        "--cpus=1.0"
        "--memory-swap=4g"
      ] ++ lib.optionals (config.hwc.infrastructure.hardware.gpu.enable or false && cfg.gpu.enable) [
        "--device=/dev/dri:/dev/dri"
      ];
      ports = [
        "127.0.0.1:8989:8989"
      ];
      volumes = [
        "${cfgRoot}/sonarr:/config"
        "${config.hwc.paths.media}/tv:/tv"
        "${config.hwc.paths.hot}/processing/sonarr-temp:/processing"
        "${config.hwc.paths.hot}/downloads:/downloads"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone or "America/Denver";
      };
      dependsOn = [ "prowlarr" ];
    };

    # Service dependencies
    systemd.services."podman-sonarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-sonarr".wants = [ "network-online.target" "agenix.service" ];
  };
}
