# domains/home/apps/qbittorrent/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.qbittorrent;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.qbittorrent = {
    enable = lib.mkEnableOption "qBittorrent torrent client";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.qbittorrent ];
  };
}
