# Radarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.radarr;
  cfgRoot = "/opt/downloads";
  mediaNetworkName = "media-network";
in
{
  config = lib.mkIf cfg.enable {
    # Container definition
    virtualisation.oci-containers.containers.radarr = {
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
        "127.0.0.1:7878:7878"
      ];
      volumes = [
        "${cfgRoot}/radarr:/config"
        "${config.hwc.paths.media}/movies:/movies"
        "${config.hwc.paths.hot}/processing/radarr-temp:/processing"
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
    systemd.services."podman-radarr".after = [ "network-online.target" "init-media-network.service" "agenix.service" ];
    systemd.services."podman-radarr".wants = [ "network-online.target" "agenix.service" ];
  };
}
