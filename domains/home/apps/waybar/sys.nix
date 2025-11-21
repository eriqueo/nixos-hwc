# domains/home/apps/waybar/sys.nix
# System-lane dependencies for Waybar status bar
#
# ARCHITECTURE NOTE:
# This sys.nix file defines system-lane options because system evaluates
# before Home Manager. See CHARTER.md Section 5 for sys.nix pattern.

{ lib, config, ... }:

let
  cfg = config.hwc.system.apps.waybar;
in
{
  #============================================================================
  # OPTIONS - System-lane API
  #============================================================================
  options.hwc.system.apps.waybar = {
    enable = lib.mkEnableOption "Waybar system dependencies and validation";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      #========================================================================
      # VALIDATION - System dependencies required by waybar modules
      #========================================================================
      assertions = [
        {
          assertion = config.hwc.system.services.hardware.audio.enable;
          message = "waybar's pulseaudio module requires hwc.system.services.hardware.audio.enable = true";
        }
        {
          assertion = config.hwc.system.services.hardware.bluetooth.enable;
          message = "waybar's bluetooth module requires hwc.system.services.hardware.bluetooth.enable = true";
        }
        {
          assertion = config.hwc.networking.enable;
          message = "waybar's network module requires hwc.networking.enable = true (for NetworkManager)";
        }
      ];
    })
    {}
  ];
}
