# domains/home/apps/opencode/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.opencode;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.opencode = {
    enable = lib.mkEnableOption "OpenCode";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.opencode ];
  };
}
