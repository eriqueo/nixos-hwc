# modules/server/containers/lidarr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.lidarr = {
    enable = mkEnableOption "lidarr container";
        image  = mkOption { type = types.str; default = "lscr.io/linuxserver/lidarr:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
