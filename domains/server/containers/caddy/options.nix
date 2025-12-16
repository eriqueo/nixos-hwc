# modules/server/containers/caddy/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.caddy = {
    enable = mkEnableOption "caddy container";
    image  = mkOption { type = types.str; default = "docker.io/library/caddy:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}