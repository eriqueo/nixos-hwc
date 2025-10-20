# Prowlarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.prowlarr;
  cfgRoot = "/opt/downloads";
  mediaNetworkName = "media-network";
in
{
  config = lib.mkIf cfg.enable {
    # Container definition
    virtualisation.oci-containers.containers.prowlarr = {
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
        "127.0.0.1:9696:9696"
      ];
      volumes = [
        "${cfgRoot}/prowlarr:/config"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone or "America/Denver";
      };
    };

    # Service dependencies
    systemd.services."podman-prowlarr".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-prowlarr".wants = [ "network-online.target" ];
  };
}
