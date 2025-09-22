# modules/server/containers/qbittorrent/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.qbittorrent = {
    enable = mkEnableOption "qbittorrent container";
        image  = mkOption { type = types.str; default = "lscr.io/linuxserver/qbittorrent"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
