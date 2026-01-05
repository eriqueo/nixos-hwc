{ lib, config, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.containers.immich = {
    enable = mkEnableOption "Immich photo management server (containerized)";

    # Container images
    images = {
      server = mkOption {
        type = types.str;
        default = "ghcr.io/immich-app/immich-server:release";
        description = "Immich server container image";
      };

      machineLearning = mkOption {
        type = types.str;
        default = "ghcr.io/immich-app/immich-machine-learning:release";
        description = "Immich machine learning container image";
      };

      redis = mkOption {
        type = types.str;
        default = "docker.io/library/redis:7.2-alpine";
        description = "Redis container image";
      };
    };

    settings = {
      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Listen address for Immich server";
      };

      port = mkOption {
        type = types.port;
        default = 2283;
        description = "Port for Immich server";
      };

      mediaLocation = mkOption {
        type = types.str;
        default = config.hwc.paths.photos or "/mnt/photos";
        description = "Path to media storage location";
      };
    };

    storage = {
      enable = mkEnableOption "Advanced storage layout with separate directories" // { default = true; };

      basePath = mkOption {
        type = types.str;
        default = config.hwc.paths.photos or "/mnt/photos";
        description = ''
          Base path for all Immich storage. All storage subdirectories will be created here.
          This path will be added to backup sources automatically.
        '';
      };

      locations = {
        library = mkOption {
          type = types.str;
          default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/library" else "/mnt/photos/library";
          description = ''
            Primary photo/video library location (UPLOAD_LOCATION).
            Storage templates configured via web UI organize files within this directory.
            Recommended storage template: {{y}}/{{MM}}/{{dd}}/{{filename}}
          '';
        };

        thumbs = mkOption {
          type = types.str;
          default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/thumbs" else "/mnt/photos/thumbs";
          description = "Thumbnail cache location (THUMB_LOCATION)";
        };

        encodedVideo = mkOption {
          type = types.str;
          default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/encoded-video" else "/mnt/photos/encoded-video";
          description = "Transcoded video storage (ENCODED_VIDEO_LOCATION)";
        };

        profile = mkOption {
          type = types.str;
          default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/profile" else "/mnt/photos/profile";
          description = "User profile pictures (PROFILE_LOCATION)";
        };
      };
    };

    database = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "PostgreSQL host";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      name = mkOption {
        type = types.str;
        default = "immich";
        description = "Database name";
      };

      user = mkOption {
        type = types.str;
        default = "immich";
        description = "Database user";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing database password (for container use)";
      };
    };

    redis = {
      enable = mkEnableOption "Redis caching for Immich" // { default = true; };

      host = mkOption {
        type = types.str;
        default = "immich-redis";
        description = "Redis host";
      };

      port = mkOption {
        type = types.port;
        default = 6379;
        description = "Redis port";
      };
    };

    gpu = {
      enable = mkEnableOption "GPU acceleration for photo/video processing";
    };

    # Observability and logging
    observability = {
      logLevel = mkOption {
        type = types.enum [ "verbose" "debug" "log" "warn" "error" ];
        default = "log";
        description = ''
          Immich log level. Options: verbose, debug, log (info), warn, error.
          Default: log (equivalent to info)
        '';
      };

      metrics = {
        enable = mkEnableOption "Prometheus metrics endpoints" // { default = true; };

        apiPort = mkOption {
          type = types.port;
          default = 8091;
          description = "Prometheus metrics port for immich-server (API metrics)";
        };

        microservicesPort = mkOption {
          type = types.port;
          default = 8092;
          description = "Prometheus metrics port for immich-machine-learning (worker metrics)";
        };
      };
    };

    # Machine learning performance tuning
    machineLearning = {
      cpuCores = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          Number of CPU cores for ML threading calculations.
          null = auto-detect from system (recommended)

          Used to compute:
          - interOpThreads = min(2, cores - 2)
          - intraOpThreads = max(1, cores - 2)
        '';
      };

      modelTTL = mkOption {
        type = types.int;
        default = 600;
        description = ''
          Time-to-live for ML models in GPU memory (seconds).
          Default: 600 (10 minutes). Increase to reduce model reload overhead,
          decrease to free GPU memory faster.
        '';
      };

      modelTTLPollInterval = mkOption {
        type = types.int;
        default = 30;
        description = ''
          How often to check if models should be unloaded (seconds).
          Default: 30 seconds (vs 10s upstream default).
        '';
      };

      threading = {
        requestThreads = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Number of concurrent ML requests to process.
            null = auto-detect (usually 1)

            WARNING: Higher values increase GPU memory usage.
          '';
        };

        interOpThreads = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Inter-op parallelism for ML models (parallel operations).
            null = auto-compute as min(2, cores - 2)

            Recommended: 2 for single-GPU systems
          '';
        };

        intraOpThreads = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Intra-op parallelism for ML models (threads per operation).
            null = auto-compute as max(1, cores - 2)

            Recommended: cores - 2 to leave headroom for other processes
          '';
        };
      };
    };

    # Reverse proxy configuration
    reverseProxy = {
      trustedProxies = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          CIDR ranges of trusted reverse proxies for correct client IP logging.

          Recommended values:
          - "127.0.0.1" (local Caddy/nginx)
          - "100.64.0.0/10" (Tailscale CGNAT range)
          - Your custom proxy network CIDR
        '';
      };
    };

    network = {
      mode = mkOption {
        type = types.enum [ "media" "host" ];
        default = "media";
        description = "Network mode: media (podman network) or host";
      };
    };

    resources = {
      server = {
        memory = mkOption {
          type = types.str;
          default = "2g";
          description = "Memory limit for immich-server";
        };

        cpus = mkOption {
          type = types.str;
          default = "2.0";
          description = "CPU limit for immich-server";
        };
      };

      machineLearning = {
        memory = mkOption {
          type = types.str;
          default = "4g";
          description = "Memory limit for immich-machine-learning";
        };

        cpus = mkOption {
          type = types.str;
          default = "4.0";
          description = "CPU limit for immich-machine-learning";
        };
      };
    };
  };
}
