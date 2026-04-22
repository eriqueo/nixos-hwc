# domains/home/apps/markitdown/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.markitdown;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.markitdown = {
    enable = lib.mkEnableOption "markitdown — convert PDF/DOCX/XLSX/images/audio to Markdown";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.python3Packages.markitdown ];
  };
}
