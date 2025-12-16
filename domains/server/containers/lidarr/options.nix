# modules/server/containers/lidarr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.lidarr = {
    enable = mkEnableOption "lidarr container";
    image  = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/lidarr:2.13.3";
      description = "Container image (pinned version - develop branch has NullRef bug in Distance.Clean())";
    };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
