# modules/server/containers/jellyfin/options.nix
{ lib, config, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  shared = config.hwc.services.shared.lib;
in
{
  options.hwc.services.containers.jellyfin = {
    enable = mkEnableOption "jellyfin container";
        image  = shared.mkImageOption { default = "lscr.io/linuxserver/jellyfin:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
