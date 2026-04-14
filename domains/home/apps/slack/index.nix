# domains/home/apps/slack/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.slack;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.slack = {
    enable = lib.mkEnableOption "Slack desktop client";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.slack ];
  };
}
