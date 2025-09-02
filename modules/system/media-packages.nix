# nixos-hwc/modules/system/media-packages.nix
#
# MEDIA PACKAGES - System-level packages for media operations
# Container management, media tools, and monitoring for media servers
#
# DEPENDENCIES (Upstream):
#   - None (base system packages)
#
# USED BY (Downstream):
#   - profiles/media-profile.nix (enables via hwc.system.mediaPackages.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/media-profile.nix: ../modules/system/media-packages.nix
#
# USAGE:
#   hwc.system.mediaPackages.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.mediaPackages;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.system.mediaPackages = {
    enable = lib.mkEnableOption "Media server system packages";
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Media server system packages
    environment.systemPackages = with pkgs; [
      # Container management
      podman-compose
      
      # Media tools
      ffmpeg
      mediainfo
      
      # Network tools
      curl
      wget
      
      # Monitoring
      htop
      iotop
    ];
  };
}