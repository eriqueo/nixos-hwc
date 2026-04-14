{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.pinchflat;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.pinchflat = {
    enable = lib.mkEnableOption "pinchflat container (YouTube subscription manager)";
    image = lib.mkOption { type = lib.types.str; default = "ghcr.io/kieraneglin/pinchflat:latest"; description = "Container image for Pinchflat"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    port = lib.mkOption { type = lib.types.port; default = 8945; description = "Port for Pinchflat web UI"; };
  };

  imports = [
    ./sys.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Pinchflat is standalone - no dependencies required
}
