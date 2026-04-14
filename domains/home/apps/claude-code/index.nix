# domains/home/apps/claude-code/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-code;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.claude-code ];
  };
}
