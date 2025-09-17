# modules/server/containers/immich/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.immich = {
    enable = mkEnableOption "immich container";
        image  = mkOption { type = types.str; default = "ghcr.io/immich-app/immich-server:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
