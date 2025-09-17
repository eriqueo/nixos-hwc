# modules/server/containers/soularr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.soularr = {
    enable = mkEnableOption "soularr container";
    image  = mkOption { type = types.str; default = "docker.io/mrusse08/soularr:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
