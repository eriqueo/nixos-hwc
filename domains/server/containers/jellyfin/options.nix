# modules/server/containers/jellyfin/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.jellyfin = {
    enable = mkEnableOption "jellyfin container";
        image  = mkOption { type = types.str; default = "lscr.io/linuxserver/jellyfin:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
