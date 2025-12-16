# modules/server/containers/navidrome/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.navidrome = {
    enable = mkEnableOption "navidrome container";
        image  = mkOption { type = types.str; default = "deluan/navidrome:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
