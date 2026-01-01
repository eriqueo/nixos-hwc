{ lib, config, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.native.immich = {
    enable = mkEnableOption "Immich photo management server (native service)";

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

      template = {
        recommended = mkOption {
          type = types.str;
          default = "{{y}}/{{MM}}/{{dd}}/{{filename}}";
          description = ''
            Recommended storage template (configure via web UI after installation).
            This organizes files by: Year/Month/Day/Filename

            Available template variables:
            - {{y}} - Year (4 digits)
            - {{yy}} - Year (2 digits)
            - {{MM}} - Month (01-12)
            - {{MMM}} - Month (Jan-Dec)
            - {{dd}} - Day (01-31)
            - {{hh}} - Hour (00-23)
            - {{mm}} - Minute (00-59)
            - {{ss}} - Second (00-59)
            - {{filename}} - Original filename
            - {{ext}} - File extension
            - {{album}} - Album name (if in album)

            Alternative templates:
            - Multi-user organized: {{y}}/{{MM}}/{{album}}/{{filename}}
            - Camera-based: {{y}}/{{MM}}/{{assetId}}/{{filename}}
            - Simple monthly: {{y}}/{{MM}}/{{filename}}
          '';
        };

        documentation = mkOption {
          type = types.str;
          default = ''
            Storage templates are configured via the Immich web UI:
            1. Log in as admin
            2. Navigate to Administration → Settings → Storage Template
            3. Use the template builder to configure your preferred structure
            4. Test the template before applying
            5. Existing files can be migrated to the new template structure

            IMPORTANT: Storage templates only affect NEW uploads. Use the migration
            job in the web UI to reorganize existing files.
          '';
          description = "Documentation for configuring storage templates";
        };
      };
    };

    backup = {
      enable = mkEnableOption "Immich data backup integration" // { default = true; };

      includeDatabase = mkOption {
        type = types.bool;
        default = true;
        description = "Include PostgreSQL database dumps in backups";
      };

      databaseBackupPath = mkOption {
        type = types.str;
        default = "/var/backup/immich-db";
        description = "Path for PostgreSQL database dumps";
      };

      schedule = mkOption {
        type = types.str;
        default = "daily";
        description = "Database backup schedule (daily/hourly)";
      };
    };

    database = {
      createDB = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to create database (false to use existing)";
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
    };

    redis = {
      enable = mkEnableOption "Redis caching for Immich";
    };

    gpu = {
      enable = mkEnableOption "GPU acceleration for photo/video processing";
    };

    # Observability and logging
    observability = {
      timezone = mkOption {
        type = types.str;
        default = "America/Denver";  # Will be overridden by config.time.timeZone in index.nix
        description = ''
          Timezone for Immich services. Ensures correct timestamps in logs and EXIF metadata processing.
          Defaults to system timezone.
        '';
      };

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

          Set in machine config:
          hwc.server.native.immich.reverseProxy.trustedProxies = [ "127.0.0.1" "100.64.0.0/10" ];
        '';
      };
    };

    # Note: Immich uses direct port access, not reverse proxy (SvelteKit issues)
    directAccess = {
      tailscaleHttps = mkOption {
        type = types.str;
        default = "https://hwc.ocelot-wahoo.ts.net:2283";
        description = "Tailscale HTTPS access URL";
      };

      localHttp = mkOption {
        type = types.str;
        default = "http://192.168.1.13:2283";
        description = "Local HTTP access URL";
      };
    };
  };
}