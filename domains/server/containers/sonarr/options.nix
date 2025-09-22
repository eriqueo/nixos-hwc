# modules/server/containers/sonarr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.sonarr = {
    enable = mkEnableOption "sonarr container";
        image  = mkOption { type = types.str; default = "lscr.io/linuxserver/sonarr:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
