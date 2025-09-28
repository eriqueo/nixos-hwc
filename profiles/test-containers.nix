{ config, lib, pkgs, ... }:
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  imports = [
    ../domains/server/containers/index.nix
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  time.timeZone = "America/Denver";

  hwc.services.reverseProxy.enable = true;
  hwc.services.reverseProxy.domain = "test.local";

  hwc.services.containers = {
    sonarr.enable   = true; sonarr.network.mode   = "media";
    radarr.enable   = true; radarr.network.mode   = "media";
    jellyfin.enable = true; jellyfin.network.mode = "media";
  };
}
