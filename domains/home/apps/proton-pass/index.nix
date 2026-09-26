# domains/home/apps/proton-pass/index.nix
{ lib, pkgs, config, ... }:
let
  cfg = config.hwc.home.apps.proton-pass;

  session    = import ./parts/session.nix    { inherit lib pkgs config; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.proton-pass = {
    enable = lib.mkEnableOption "Proton Pass password manager";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = (session.packages or []);
  };
}
