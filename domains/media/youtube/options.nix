# domains/server/native/youtube/options.nix
#
# YouTube content acquisition APIs - transcripts and video downloads
#
# NAMESPACE: hwc.server.native.youtube.*
#
# USED BY:
#   - profiles/server.nix
#   - domains/server/native/monitoring/prometheus (health checks)

{ lib, config, ... }:

let
  paths = config.hwc.paths or {};
in
{
  options.hwc.server.native.youtube = {
    #==========================================================================
    # TRANSCRIPTS API (newer, FastAPI-based)
    #==========================================================================
    transcripts = {
      enable = lib.mkEnableOption "YouTube transcripts extraction API";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8100;
        description = "API server port";
      };

      workers = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4;
        description = "Number of background worker processes";
      };

      outputDirectory = lib.mkOption {
        type = lib.types.path;
        default = "${paths.hot or "/mnt/hot"}/youtube-transcripts";
        description = "Directory for transcript output files";
      };

      rateLimit = {
        requestsPerSecond = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = "HTTP rate limit (requests per second for scraping)";
        };

        burst = lib.mkOption {
          type = lib.types.ints.positive;
          default = 50;
          description = "HTTP rate limit burst capacity";
        };

        quotaLimit = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10000;
          description = "YouTube Data API quota limit (units per day)";
        };
      };

      defaultOutputFormat = lib.mkOption {
        type = lib.types.enum [ "markdown" "jsonl" ];
        default = "markdown";
        description = "Default transcript output format";
      };
    };

    #==========================================================================
    # VIDEOS API (yt-dlp based downloads)
    #==========================================================================
    videos = {
      enable = lib.mkEnableOption "YouTube video download and archiving API";

      port = lib.mkOption {
        type = lib.types.port;
        default = 8101;
        description = "API server port";
      };

      workers = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Number of background download workers";
      };

      outputDirectory = lib.mkOption {
        type = lib.types.path;
        default = "${paths.media.root or "/mnt/media"}/youtube";
        description = "Directory for downloaded videos";
      };

      containerPolicy = lib.mkOption {
        type = lib.types.enum [ "webm" "mp4" "mkv" ];
        default = "webm";
        description = "Default container format for downloads";
      };

      qualityPreference = lib.mkOption {
        type = lib.types.str;
        default = "best";
        description = "yt-dlp quality selector (e.g., 'best', '1080p', 'bestvideo+bestaudio')";
      };

      embedMetadata = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Embed metadata (title, channel, date) into video files";
      };

      embedCoverArt = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Embed cover art/thumbnails into video files";
      };

      stagingDirectory = lib.mkOption {
        type = lib.types.path;
        default = "${paths.media.root or "/mnt/media"}/youtube/.staging";
        description = "Staging directory for in-progress downloads (auto-derived from outputDirectory)";
      };

      rateLimit = {
        requestsPerSecond = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10;
          description = "HTTP rate limit for yt-dlp scraping";
        };

        burst = lib.mkOption {
          type = lib.types.ints.positive;
          default = 50;
          description = "HTTP rate limit burst capacity";
        };

        quotaLimit = lib.mkOption {
          type = lib.types.ints.positive;
          default = 10000;
          description = "YouTube Data API quota limit (units per day)";
        };
      };
    };

    #==========================================================================
    # LEGACY TRANSCRIPT API (older implementation)
    #==========================================================================
    legacyApi = {
      enable = lib.mkEnableOption "Legacy YouTube transcript API";

      port = lib.mkOption {
        type = lib.types.port;
        default = 5000;
        description = "API port";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.vaults or "/home/eric/900_vaults"}/transcripts";
        description = "Transcripts vault directory (where finished .md files are saved)";
      };

      apiKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "YouTube API keys";
      };
    };
  };
}
