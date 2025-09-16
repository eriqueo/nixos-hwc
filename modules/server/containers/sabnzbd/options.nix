# modules/server/containers/sabnzbd/options.nix
{ lib, config, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  shared = config.hwc.services.shared.lib;
in
{
  options.hwc.services.containers.sabnzbd = {
    enable = mkEnableOption "sabnzbd container";
        image  = shared.mkImageOption { default = "lscr.io/linuxserver/sabnzbd:latest"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
