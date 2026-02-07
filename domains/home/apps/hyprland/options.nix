# modules/home/apps/hyprland/options.nix
{ lib, osConfig ? {}, ... }:

{
  options.hwc.home.apps.hyprland = {
    enable = lib.mkEnableOption "Enable Hyprland (HM)";

    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable notification daemon integration";
    };

    cursor = {
      theme = lib.mkOption {
        type = lib.types.str;
        default = "Adwaita";
        description = "Cursor theme for Hyprland";
      };
      size = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Cursor size for Hyprland";
      };
    };
  };
}