# domains/home/apps/waybar/sys.nix - System-side validation for waybar
{ lib, config, ... }:
let
  # Check if home options are available (they might not be during system-only imports)
  cfg = lib.attrByPath ["hwc" "home" "apps" "waybar"] { enable = false; } config;
in
{
  config = lib.mkIf cfg.enable {
    #==========================================================================
    # VALIDATION
    #==========================================================================
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
        assertion = config.hwc.system.services.networking.enable;
        message = "waybar's network module requires hwc.system.services.networking.enable = true (for nmcli)";
      }
      {
        assertion = config.hwc.system.services.media.mpd.enable;
        message = "waybar's mpd module requires hwc.system.services.media.mpd.enable = true";
      }
    ];
  };
}
