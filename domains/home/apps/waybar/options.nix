# modules/home/apps/waybar/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.waybar.enable =
    lib.mkEnableOption "Enable Waybar";

  options.hwc.infrastructure.waybarTools = {
    enable = lib.mkEnableOption "Waybar system helper tools (compat)";
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show notifications for Waybar tool actions (compat).";
    };
  };
}