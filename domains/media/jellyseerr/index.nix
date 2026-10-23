{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.jellyseerr;
  appVersion = "3.1.0";
  nodeVersion = "22.23.4";
  upstreamImage = "ghcr.io/seerr-team/seerr@sha256:b35ba0461c4a1033d117ac1e5968fd4cbe777899e4cbfbdeaf3d10a42a0eb7e9";
  nodeSourceImage = "ghcr.io/seerr-team/seerr@sha256:d8fab675b55ad293ded98fd71efcfd46054cbad9746534ae1cc4794a88c0b3be";
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  # Temporary: 3.5 removes a column needed by 3.1 authentication on recovery.
  # Remove after an upstream app release passes current-data recovery/consumer
  # qualification (brain-w8phr6); this does not fix older app advisories.
  runtime = helpers.mkNodeRuntimeImage {
    name = "seerr";
    inherit appVersion nodeVersion upstreamImage nodeSourceImage;
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.jellyseerr = {
    enable = lib.mkEnableOption "jellyseerr container";
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified container image; local default built from system.build.seerrRuntimeImageRecipe"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/setup.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.seerrRuntimeImageRecipe = runtime.dockerfile;
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
