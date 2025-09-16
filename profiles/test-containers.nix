{ config, lib, pkgs, ... }:
{
  imports = [
    ../modules/services/containers
  ];

  time.timeZone = "America/Denver";

  hwc.services.reverseProxy.enable = true;
  hwc.services.reverseProxy.domain = "test.local";

  hwc.services.containers = {
    sonarr.enable   = true; sonarr.network.mode   = "media";
    radarr.enable   = true; radarr.network.mode   = "media";
    jellyfin.enable = true; jellyfin.network.mode = "media";
  };
}
