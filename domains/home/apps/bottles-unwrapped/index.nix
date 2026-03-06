# domains/home/apps/bottles-unwrapped/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.bottles-unwrapped;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.bottles-unwrapped = {
    enable = lib.mkEnableOption "Bottles Wine manager (unwrapped)";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.bottles-unwrapped ];
  };
}