# domains/home/apps/proton-authenticator/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.proton-authenticator;
  toggleScript = import ./parts/toggle-script.nix { inherit pkgs; };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.proton-authenticator = {
    enable = lib.mkEnableOption "Proton Authenticator";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.proton-authenticator toggleScript ];
  };
}
