# Co-located system lane for Waybar (temporary compat options)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.waybarTools;
in {
  config = lib.mkIf cfg.enable {
    # later you can add environment.systemPackages, user services, scripts, etc.
  };
}
