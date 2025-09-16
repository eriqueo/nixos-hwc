# modules/home/apps/chromium/sys.nix
#
# Chromium Browser - System integration glue (no packages)
# Provides system-side helpers for Chromium integration with gpu-launch
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.session.chromium;
in {
  #============================================================================
  # IMPLEMENTATION - System Integration Only
  #============================================================================
  config = lib.mkIf cfg.enable {
    # System-side helpers for Chromium (no packages - HM handles those)
    # Ensure dconf is available for browser settings
    programs.dconf.enable = lib.mkDefault true;
    
    # D-Bus services needed for portal integration
    services.dbus.enable = lib.mkDefault true;
    
    # No environment.systemPackages - HM provides the chromium binary
    # gpu-launch will find it via user PATH when running as user
  };
}