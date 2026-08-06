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
