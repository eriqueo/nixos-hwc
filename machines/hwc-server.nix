{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware/hwc-server.nix
    ../profiles/base.nix
    ../profiles/server-base.nix
    ../profiles/media.nix
    ../profiles/monitoring.nix
    ../profiles/business.nix
    ../profiles/ai.nix
    ../profiles/security.nix
  ];
  
  networking.hostName = "hwc-server";
  networking.hostId = "8425e349";
  
  # Production paths
  hwc.paths = {
    hot = "/mnt/hot";
    media = "/mnt/media";
  };
  
  # Storage UUIDs (update with actual values)
  hwc.storage.hot.device = "/dev/disk/by-uuid/ACTUAL-UUID-HERE";
  
  # Machine-specific overrides
  hwc.services.jellyfin.port = 8096;
  hwc.gpu.nvidia.enable = true;
  
  system.stateVersion = "24.05";
}
