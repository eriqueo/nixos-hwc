{ config, lib, pkgs, nixosConfig, ... }:
let
  wcfg = nixosConfig.hwc.home.waybar or {};
  on = x: (x or false);
in {
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
}
