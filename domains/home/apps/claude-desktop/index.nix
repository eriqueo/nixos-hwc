# domains/home/apps/claude-desktop/index.nix
#
# Claude Desktop GUI (Electron) — community Linux port
# Provides cowork, dispatch, and full desktop experience.
# Source: github:k3d3/claude-desktop-linux-flake
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.home.apps.claude-desktop;
  system = pkgs.stdenv.hostPlatform.system;
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
      inputs.claude-desktop.packages.${system}.claude-desktop-with-fhs
    ];
  };
}
