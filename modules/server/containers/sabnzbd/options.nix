# modules/server/containers/sabnzbd/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.sabnzbd = {
    enable = mkEnableOption "sabnzbd container";
        image  = mkOption { type = types.str; default = "lscr.io/linuxserver/sabnzbd:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
