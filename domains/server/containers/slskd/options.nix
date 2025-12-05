# modules/server/containers/slskd/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.slskd = {
    enable = mkEnableOption "slskd container";
    image  = mkOption {
      type = types.str;
      default = "slskd/slskd:0.21.4";
      description = "Container image (pinned for stability)";
    };
    network.mode = mkOption { type = types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable    = mkOption { type = types.bool; default = true; };
  };
}
