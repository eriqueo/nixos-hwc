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
        # media.root is non-null on every host that imports this domain (server role)
        default = "${config.hwc.paths.media.root}/transcripts";
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
  };

  imports = [
    ./parts/yt-transcripts-api
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
