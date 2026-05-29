# domains/home/apps/xournalpp/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.xournalpp;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.xournalpp = {
    enable = lib.mkEnableOption "xournalpp PDF annotator and note-taker";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.xournalpp ];
  };
}
