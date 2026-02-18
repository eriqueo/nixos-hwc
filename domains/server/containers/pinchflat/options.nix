# domains/server/containers/pinchflat/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.pinchflat = {
    enable = mkEnableOption "pinchflat container (YouTube subscription manager)";
    image = mkOption {
      type = types.str;
      default = "ghcr.io/kieraneglin/pinchflat:latest";
      description = "Container image for Pinchflat";
    };
    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode (media network or VPN)";
    };
    port = mkOption {
      type = types.port;
      default = 8945;
      description = "Port for Pinchflat web UI";
    };
  };
}
