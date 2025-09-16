# modules/server/containers/caddy/options.nix
{ lib, config, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  shared = config.hwc.services.shared.lib;
in
{
  options.hwc.services.containers.caddy = {
    enable = mkEnableOption "caddy container";
    image  = shared.mkImageOption { default = "docker.io/library/caddy:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}