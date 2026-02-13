# domains/server/containers/readarr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.readarr = {
    enable = mkEnableOption "readarr container";
    image  = mkOption { type = types.str; default = "lscr.io/linuxserver/readarr:0.4.10-nightly"; description = "Container image"; };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = false; };
  };
}
