# modules/server/containers/jellyseerr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.jellyseerr = {
    enable = mkEnableOption "jellyseerr container";
    image  = mkOption { type = types.str; default = "docker.io/fallenbagel/jellyseerr:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = false; };
  };
}
