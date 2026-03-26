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
let
  paths = config.hwc.paths;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.youtube = {
    transcripts = {
      enable = lib.mkEnableOption "YouTube transcripts extraction API";
      port = lib.mkOption { type = lib.types.port; default = 8100; description = "API server port"; };
      workers = lib.mkOption { type = lib.types.ints.positive; default = 4; description = "Number of background worker processes"; };
      outputDirectory = lib.mkOption { type = lib.types.path; default = "${toString paths.hot.root}/youtube-transcripts"; description = "Directory for transcript output files"; };
      rateLimit = {
        requestsPerSecond = lib.mkOption { type = lib.types.ints.positive; default = 10; };
        burst = lib.mkOption { type = lib.types.ints.positive; default = 50; };
        quotaLimit = lib.mkOption { type = lib.types.ints.positive; default = 10000; };
      };
      defaultOutputFormat = lib.mkOption { type = lib.types.enum [ "markdown" "jsonl" ]; default = "markdown"; };
    };
    videos = {
      enable = lib.mkEnableOption "YouTube video download and archiving API";
      port = lib.mkOption { type = lib.types.port; default = 8101; };
      workers = lib.mkOption { type = lib.types.ints.positive; default = 2; };
      outputDirectory = lib.mkOption { type = lib.types.path; default = toString paths.media.youtube; };
      containerPolicy = lib.mkOption { type = lib.types.enum [ "webm" "mp4" "mkv" ]; default = "webm"; };
      qualityPreference = lib.mkOption { type = lib.types.str; default = "best"; };
      embedMetadata = lib.mkOption { type = lib.types.bool; default = true; };
      embedCoverArt = lib.mkOption { type = lib.types.bool; default = true; };
      stagingDirectory = lib.mkOption { type = lib.types.path; default = "${paths.media.youtube}/.staging"; };
      rateLimit = {
        requestsPerSecond = lib.mkOption { type = lib.types.ints.positive; default = 10; };
        burst = lib.mkOption { type = lib.types.ints.positive; default = 50; };
        quotaLimit = lib.mkOption { type = lib.types.ints.positive; default = 10000; };
      };
    };
    legacyApi = {
      enable = lib.mkEnableOption "Legacy YouTube transcript API";
      port = lib.mkOption { type = lib.types.port; default = 5000; };
      dataDir = lib.mkOption { type = lib.types.path; default = "${toString paths.user.vaults}/transcripts"; };
      apiKeys = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    };
  };

  imports = [
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
