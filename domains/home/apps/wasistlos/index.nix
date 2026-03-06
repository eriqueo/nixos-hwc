# domains/home/apps/wasistlos/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.wasistlos;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.wasistlos = {
    enable = lib.mkEnableOption "WasIstLos WhatsApp client";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.wasistlos ];
  };
}
