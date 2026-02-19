# modules/server/containers/gluetun/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.gluetun = {
    enable = mkEnableOption "gluetun container";
    image  = mkOption { type = types.str; default = "qmcgaw/gluetun:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };

    portForwarding = {
      enable = mkEnableOption "VPN port forwarding via NAT-PMP";

      syncToQbittorrent = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically sync forwarded port to qBittorrent";
      };

      checkInterval = mkOption {
        type = types.int;
        default = 60;
        description = "Seconds between port sync checks";
      };
    };
  };
}