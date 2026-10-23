{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.jellyseerr;
  appVersion = "3.1.0";
  nodeVersion = "22.23.4";
  upstreamImage = "ghcr.io/seerr-team/seerr@sha256:b35ba0461c4a1033d117ac1e5968fd4cbe777899e4cbfbdeaf3d10a42a0eb7e9";
  nodeSourceImage = "ghcr.io/seerr-team/seerr@sha256:d8fab675b55ad293ded98fd71efcfd46054cbad9746534ae1cc4794a88c0b3be";
  # Temporary: 3.5 removes a column needed by 3.1 authentication on recovery.
  # Remove after an upstream app release passes current-data recovery/consumer
  # qualification (brain-w8phr6); this does not fix older app advisories.
  runtimeRecipe = ''
    FROM ${nodeSourceImage} AS secure-node
    FROM ${upstreamImage}
    COPY --from=secure-node /usr/local/bin/node /usr/local/bin/node
    ENV NODE_VERSION=${nodeVersion}
  '';
  runtimeImage = "localhost/seerr-runtime:${appVersion}-node${nodeVersion}-${builtins.substring 0 12 (builtins.hashString "sha256" runtimeRecipe)}";
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.jellyseerr = {
    enable = lib.mkEnableOption "jellyseerr container";
    image = lib.mkOption { type = lib.types.str; default = upstreamImage; description = "Recovery image pinned to the exact prior app/runtime; settings preservation stays enabled"; };
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
    system.build.seerrRuntimeImageRecipe = pkgs.writeText "seerr-runtime.Dockerfile" runtimeRecipe;
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
