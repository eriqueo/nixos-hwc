# Co-located system lane for Waybar (temporary compat options)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.waybarTools;
in {
  options.hwc.infrastructure.waybarTools = {
    enable = lib.mkEnableOption "Waybar system helper tools (compat)";
    notifications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show notifications for Waybar tool actions (compat).";
    };
  };

  config = lib.mkIf cfg.enable {
    # later you can add environment.systemPackages, user services, scripts, etc.
  };
}
