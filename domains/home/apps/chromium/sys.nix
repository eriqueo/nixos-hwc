# modules/home/apps/chromium/sys.nix
#
# Chromium Browser - System integration glue (no packages)
# Provides basic system integration for Chromium (dconf, dbus)
# GPU acceleration handled via existing gpu-launch infrastructure
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.chromium;
in {
  imports = [ ./options.nix ];
  #============================================================================
  # IMPLEMENTATION - System Integration Only
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Basic system integration for Chromium browser
    # Ensure dconf is available for browser settings
    programs.dconf.enable = lib.mkDefault true;
    
    # D-Bus services needed for portal integration
    services.dbus.enable = lib.mkDefault true;
    
    # No environment.systemPackages - HM provides the chromium binary
    # GPU acceleration via gpu-launch command (from infrastructure.hardware.gpu)
  };
}