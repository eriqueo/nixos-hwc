# modules/server/containers/prowlarr/options.nix
{ lib, config, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  shared = config.hwc.services.shared.lib;
in
{
  options.hwc.services.containers.prowlarr = {
    enable = mkEnableOption "prowlarr container";
        image  = shared.mkImageOption { default = "lscr.io/linuxserver/prowlarr:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
