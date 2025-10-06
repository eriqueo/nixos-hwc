# modules/home/apps/hyprland/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.hyprland.enable =
    lib.mkEnableOption "Enable Hyprland (HM)";

  options.hwc.infrastructure.hyprlandTools = {
    enable = lib.mkEnableOption "Hyprland system helpers (compat; no system effects in HM-only mode)";
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Compat flag used by profiles; no system-side behavior in HM-only setup.";
    };
    cursor = {
      theme = lib.mkOption {
        type = lib.types.str;
        default = "Adwaita";
        description = "Declared for compatibility; applied by Home Manager only.";
      };
      size  = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Declared for compatibility; applied by Home Manager only.";
      };
    };
  };
}
