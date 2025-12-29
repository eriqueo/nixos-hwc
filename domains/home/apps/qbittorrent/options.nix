{ lib, ... }:

{
  options.hwc.home.apps.qbittorrent = {
    enable = lib.mkEnableOption "qBittorrent desktop client";
  };
}
