{ lib, ... }:
{
  options.hwc.home.apps.hyprland = {
    enable = lib.mkEnableOption "Enable Hyprland (Home scope)";
  };
}
