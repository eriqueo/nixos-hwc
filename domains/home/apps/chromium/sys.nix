# domains/home/apps/chromium/sys.nix
# System-lane dependencies for Chromium browser
#
# ARCHITECTURE NOTE:
# This sys.nix file defines system-lane options because system evaluates
# before Home Manager. See CHARTER.md Section 5 for sys.nix pattern.

{ config, lib, ... }:

let
  cfg = config.hwc.system.apps.chromium;
in
{
  #============================================================================
  # OPTIONS - System-lane API
  #============================================================================
  options.hwc.system.apps.chromium = {
    enable = lib.mkEnableOption "Chromium system integration (dconf, dbus)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      #========================================================================
      # SYSTEM INTEGRATION
      #========================================================================
      # Basic system integration for Chromium browser
      # Ensure dconf is available for browser settings
      programs.dconf.enable = lib.mkDefault true;

      # D-Bus services needed for portal integration
      services.dbus.enable = lib.mkDefault true;

      # No environment.systemPackages - HM provides the chromium binary
      # GPU acceleration via gpu-launch command (from infrastructure.hardware.gpu)
    })
    {}
  ];
}