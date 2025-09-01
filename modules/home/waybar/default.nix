{ config, lib, pkgs, nixosConfig, ... }:

# nixos-hwc/modules/home/waybar/default.nix
#
# WAYBAR - Wayland status bar configuration
# Provides Waybar layout and module settings for the HWC environment
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (imports via home-manager)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/home/waybar/default.nix
#
# USAGE:
#   home-manager.users.<name>.imports = [ ../modules/home/waybar/default.nix ];
#
let
  wcfg = nixosConfig.hwc.home.waybar or {};
  on = x: if x != null then x else false;
in {
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf (on wcfg.enable) {
    programs.waybar = {
      enable = true;
      style = lib.mkIf (wcfg.theme == "deep-nord") (import ./theme-deep-nord.nix);
      settings = {
        mainBar = {
          layer = "top";
          position = wcfg.position;
          modules-left = lib.optional (on wcfg.modules.workspaces.enable) "hyprland/workspaces";
          modules-center = [ ];
          modules-right = lib.concatLists [
            (lib.optional (on wcfg.modules.sysmon.enable) "cpu")
            (lib.optional (on wcfg.modules.network.enable) "network")
            (lib.optional (on wcfg.modules.battery.enable) "battery")
            (lib.optional (on wcfg.modules.gpu.enable) "custom/gpu")
            [ "clock" ]
          ];
          "custom/gpu" = lib.mkIf (on wcfg.modules.gpu.enable) {
            format = "{}";
            return-type = "json";
            exec = "waybar-gpu-status";
            interval = wcfg.modules.gpu.intervalSeconds or 5;
            on-click = "waybar-gpu-toggle";
          };
        };
      };
    };
  };
