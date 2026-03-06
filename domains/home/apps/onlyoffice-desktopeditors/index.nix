# domains/home/apps/onlyoffice-desktopeditors/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.onlyoffice-desktopeditors;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.onlyoffice-desktopeditors = {
    enable = lib.mkEnableOption "OnlyOffice Desktop Editors";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.onlyoffice-desktopeditors ];
  };
}
