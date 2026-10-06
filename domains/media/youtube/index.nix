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
        description = "Default directory for transcript output files (first of outputRoots).";
      };
      outputRoots = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [
          "${config.hwc.paths.media.root}/transcripts"
          config.hwc.paths.media.youtube
        ];
        description = ''
          Whitelist of base locations the UI offers as save targets (a dropdown);
          the user names a subfolder under the chosen one. These are the ONLY
          paths the sandbox grants write access to (ReadWritePaths), so a base
          outside this list is rejected. Keep them on the media disk — a /home
          path would additionally need ProtectHome relaxed.
        '';
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
      whisper = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.hwc.server.ai.whisper.enable or false;
          defaultText = lib.literalExpression "config.hwc.server.ai.whisper.enable";
          description = ''
            When captions cannot be fetched (none exist, or YouTube is blocking
            this server), download the audio and transcribe it with the local
            whisper-server. Job requests only; POST /transcript stays captions-only.
          '';
        };
        maxDuration = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10800;
          description = ''
            Longest video (seconds) sent to Whisper. Measured ~10x real time on
            the P1000 with small.en, so the 3 h default holds the shared server
            for about 18 minutes.
          '';
        };
      };
    };
  };

  imports = [
    ./parts/transcripts
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
