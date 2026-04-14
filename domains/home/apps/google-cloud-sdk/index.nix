# domains/home/apps/google-cloud-sdk/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.google-cloud-sdk;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.google-cloud-sdk = {
    enable = lib.mkEnableOption "Google Cloud SDK";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.google-cloud-sdk ];
  };
}
