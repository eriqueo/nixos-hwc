# domains/media/youtube/index.nix
#
# YouTube content acquisition domain aggregator
# Consolidates transcript and video download services
#
# NAMESPACE: hwc.media.youtube.*
#
# USED BY:
#   - domains/server/native/index.nix
#   - profiles/server.nix

{ lib, config, pkgs, ... }:

{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./parts/legacy-api.nix
    ./parts/yt-transcripts-api
    ./parts/yt-videos-api
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Assertions are defined in individual part files
}
