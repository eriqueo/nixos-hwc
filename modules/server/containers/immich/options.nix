# modules/server/containers/immich/options.nix
{ lib, config, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  shared = config.hwc.services.shared.lib;
in
{
  options.hwc.services.containers.immich = {
    enable = mkEnableOption "immich container";
        image  = shared.mkImageOption { default = "ghcr.io/immich-app/immich-server:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
