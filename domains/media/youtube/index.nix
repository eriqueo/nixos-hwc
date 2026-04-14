# domains/media/youtube/index.nix
#
# YouTube content acquisition domain aggregator
#
# NAMESPACE: hwc.media.youtube.*
#
# USED BY:
#   - profiles/server.nix

{ lib, config, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.youtube = {
    transcripts = {
      enable = lib.mkEnableOption "YouTube transcripts extraction API";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8100;
        description = "API server port";
      };
      outputDirectory = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/media/transcripts";
        description = "Directory for transcript output files";
      };
      defaultFormat = lib.mkOption {
        type = lib.types.enum [ "raw" "basic" "llm" ];
        default = "raw";
        description = "Default cleaning format (raw=none, basic=spaCy, llm=Ollama polish)";
      };
      languages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "en" "en-US" "en-GB" ];
        description = "Preferred transcript languages in priority order";
      };
    };
    legacyApi = {
      enable = lib.mkEnableOption "Legacy YouTube transcript API";
      port = lib.mkOption { type = lib.types.port; default = 5000; };
      dataDir = lib.mkOption { type = lib.types.path; default = "/home/eric/01-documents/01-vaults/04-transcripts"; };
      apiKeys = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    };
  };

  imports = [
    ./parts/legacy-api.nix
    ./parts/yt-transcripts-api
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
