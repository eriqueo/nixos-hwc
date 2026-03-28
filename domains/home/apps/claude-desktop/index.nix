# domains/home/apps/claude-desktop/index.nix
#
# Claude Desktop GUI (Electron) — community Linux port
# Provides cowork, dispatch, and full desktop experience.
# Source: github:aaddrick/claude-desktop-debian
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-desktop;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.claude-desktop = {
    enable = lib.mkEnableOption "Claude Desktop GUI (community Linux port)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.claude-desktop-fhs
    ];
  };
}
