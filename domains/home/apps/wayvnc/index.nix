# domains/home/apps/wayvnc/index.nix
# Wayland VNC server with optional virtual output for second-screen setups.

{ config, lib, pkgs, osConfig, ... }:

let
  cfg = config.hwc.home.apps.wayvnc;

  baseSettings =
    {
      address = cfg.network.address;
      port = cfg.network.port;
    }
    // (lib.optionalAttrs cfg.virtualOutput.enable { output = cfg.virtualOutput.name; });

  virtualOutputCmd =
    "${pkgs.wlr-randr}/bin/wlr-randr --output ${cfg.virtualOutput.name} --on --mode ${cfg.virtualOutput.mode}"
    + (lib.optionalString (cfg.virtualOutput.position != "") " --pos ${cfg.virtualOutput.position}");
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.wlr-randr ];

    services.wayvnc = {
      enable = true;
      autoStart = cfg.autoStart;
      settings = lib.mkMerge [
        baseSettings
        cfg.settings
      ];
    };

    systemd.user.services.wayvnc = lib.mkIf cfg.virtualOutput.enable {
      Service.ExecStartPre = [ virtualOutputCmd ];
    };

    #======================================================================
    # VALIDATION
    #======================================================================
    assertions = [
      {
        assertion = osConfig.hwc.system.apps.hyprland.enable or false;
        message = "hwc.home.apps.wayvnc requires hwc.system.apps.hyprland enabled to ensure the Wayland session and helpers.";
      }
      {
        assertion = cfg.virtualOutput.mode != "";
        message = "hwc.home.apps.wayvnc.virtualOutput.mode cannot be empty.";
      }
    ];
  };
}
