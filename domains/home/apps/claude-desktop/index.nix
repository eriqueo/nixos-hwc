# domains/home/apps/claude-desktop/index.nix
#
# Claude Desktop GUI (Electron) — community Linux port
# Provides cowork, dispatch, and full desktop experience.
# Source: github:heytcass/claude-for-linux
{ config, lib, pkgs, inputs, ... }:
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
  imports = [ inputs.claude-for-linux.homeManagerModules.default ];

  config = lib.mkIf cfg.enable {
    programs.claude-desktop = {
      enable = true;
      fhs = true;
    };
  };
}
