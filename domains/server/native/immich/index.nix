# Immich Photo Management Server
#
# GPU ACCELERATION CONFIGURATION
# ================================================================================================
# This module implements comprehensive NVIDIA CUDA acceleration for Immich, providing:
#
# 1. ONNX Runtime CUDA Backend (CRITICAL - 2-5x ML performance boost):
#    - ONNXRUNTIME_PROVIDER="cuda" forces CUDA backend for Smart Search and Facial Recognition
#    - TensorRT cache for optimized inference (optional but recommended)
#
# 2. SystemD Service Dependencies:
#    - Requires nvidia-container-toolkit-cdi-generator.service to prevent race conditions
#    - Ensures CDI devices are available before Immich services start
#
# 3. Memory Locking Optimizations:
#    - LimitMEMLOCK="infinity" allows CUDA to lock GPU memory for better performance
#    - Critical for ML workloads to avoid memory thrashing
#
# 4. Process Priority:
#    - immich-server: Nice=-5 for responsive media processing
#    - immich-machine-learning: Nice=-10 (higher priority) for responsive AI features
#
# 5. GPU Device Access:
#    - Full NVIDIA device access (/dev/nvidia*, /dev/dri/*)
#    - Supplementary groups (video, render) for proper permissions
#
# 6. Cache Directories:
#    - /var/lib/immich/.cache/tensorrt - TensorRT optimization cache
#    - /var/lib/immich/.cache - Transformers model cache
#    - /var/lib/immich/.config/matplotlib - Matplotlib configuration
#
# VALIDATION:
# - Run: workspace/monitoring/immich-gpu-check.sh
# - Monitor: watch -n 1 nvidia-smi
# - Logs: journalctl -u immich-machine-learning -f
#
# EXPECTED PERFORMANCE:
# - Smart Search indexing: 2-5x faster
# - Facial recognition: 2-5x faster
# - Thumbnail generation: 1.5-3x faster (with hardware encoding)
# ================================================================================================

{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.immich;

  # Auto-detect CPU cores from /proc/cpuinfo or use configured value
  # Fallback to safe default of 4 if detection fails
  detectedCpuCores = let
    cpuinfoPath = /proc/cpuinfo;
    cpuinfoContent = builtins.readFile cpuinfoPath;
    processorLines = lib.filter (line: lib.hasPrefix "processor" line) (lib.splitString "\n" cpuinfoContent);
  in builtins.length processorLines;

  cpuCores =
    if cfg.machineLearning.cpuCores != null
    then cfg.machineLearning.cpuCores
    else if builtins.pathExists /proc/cpuinfo
    then detectedCpuCores
    else 4; # Safe fallback

  # ML threading configuration (auto-computed if not explicitly set)
  mlInterOpThreads =
    if cfg.machineLearning.threading.interOpThreads != null
    then cfg.machineLearning.threading.interOpThreads
    else (if 2 < (cpuCores - 2) then 2 else (cpuCores - 2));

  mlIntraOpThreads =
    if cfg.machineLearning.threading.intraOpThreads != null
    then cfg.machineLearning.threading.intraOpThreads
    else (if 1 > (cpuCores - 2) then 1 else (cpuCores - 2));

  mlRequestThreads =
    if cfg.machineLearning.threading.requestThreads != null
    then cfg.machineLearning.threading.requestThreads
    else 1; # Conservative default

  # Trusted proxy string (comma-separated list for IMMICH_TRUSTED_PROXIES)
  trustedProxiesStr = lib.concatStringsSep "," cfg.reverseProxy.trustedProxies;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Native Immich service configuration
    services.immich = {
      enable = true;
      host = cfg.settings.host;
      port = cfg.settings.port;
      # mediaLocation should be base path when storage.enable is true
      # Immich appends /library, /thumbs, etc. automatically based on environment variables
      mediaLocation = if cfg.storage.enable
        then cfg.storage.basePath
        else cfg.settings.mediaLocation;
      database = {
        createDB = cfg.database.createDB;
        name = cfg.database.name;
        user = cfg.database.user;
      };
      redis.enable = cfg.redis.enable;

      # Configure separate storage locations via environment variables
      # Note: UPLOAD_LOCATION should be the base path - Immich appends /library automatically
      environment = lib.mkIf cfg.storage.enable {
        UPLOAD_LOCATION = cfg.storage.basePath;
        THUMB_LOCATION = cfg.storage.locations.thumbs;
        ENCODED_VIDEO_LOCATION = cfg.storage.locations.encodedVideo;
        PROFILE_LOCATION = cfg.storage.locations.profile;
      };
    };

    # PostgreSQL user setup for permission simplification
    # Service runs as eric system user → connects via Unix socket peer auth → needs eric database user
    services.postgresql = {
      ensureUsers = [{
        name = "eric";
        ensureDBOwnership = false;  # Don't change database ownership, just grant access
        ensureClauses.superuser = true;  # Allow extension management and migrations
      }];
    };

    # Create storage directories (owned by eric for simplified permissions)
    systemd.tmpfiles.rules =
      (if cfg.storage.enable then [
        "z ${cfg.storage.basePath} 0755 eric users -"  # 'z' sets ownership even if directory exists, 755 for traversal
        "d ${cfg.storage.locations.library} 0750 eric users -"
        "d ${cfg.storage.locations.thumbs} 0750 eric users -"
        "d ${cfg.storage.locations.encodedVideo} 0750 eric users -"
        "d ${cfg.storage.locations.profile} 0750 eric users -"
        "d ${cfg.backup.databaseBackupPath} 0750 postgres postgres -"
        # Create .immich marker files for mount verification
        "f ${cfg.storage.locations.library}/.immich 0600 eric users -"
        "f ${cfg.storage.locations.thumbs}/.immich 0600 eric users -"
        "f ${cfg.storage.locations.encodedVideo}/.immich 0600 eric users -"
        "f ${cfg.storage.locations.profile}/.immich 0600 eric users -"
      ] else []) ++ (if cfg.gpu.enable then [
        # GPU cache directories for ML optimizations
        "d /var/lib/immich/.cache 0750 eric users -"
        "d /var/lib/immich/.cache/tensorrt 0750 eric users -"
        "d /var/lib/immich/.config 0750 eric users -"
        "d /var/lib/immich/.config/matplotlib 0750 eric users -"
      ] else []);

    # PostgreSQL database backup service
    services.postgresqlBackup = lib.mkIf (cfg.backup.enable && cfg.backup.includeDatabase) {
      enable = true;
      databases = [ cfg.database.name ];
      location = cfg.backup.databaseBackupPath;
      startAt = if cfg.backup.schedule == "hourly" then "hourly" else "*-*-* 02:00:00";
      compression = "zstd";
    };

    # SystemD services configuration
    systemd.services = lib.mkMerge [
      # Grant eric user access to immich database and schemas (permission simplification)
      {
        postgresql.postStart = lib.mkAfter ''
          $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON DATABASE ${cfg.database.name} TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "GRANT USAGE, CREATE ON SCHEMA public TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO eric;" || true

          # Grant access to vectors schema (created by pgvector extension)
          $PSQL -d ${cfg.database.name} -c "GRANT USAGE, CREATE ON SCHEMA vectors TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA vectors TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA vectors TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA vectors TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA vectors GRANT ALL ON TABLES TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA vectors GRANT ALL ON SEQUENCES TO eric;" || true
          $PSQL -d ${cfg.database.name} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA vectors GRANT ALL ON FUNCTIONS TO eric;" || true
        '';
      }

      # GPU acceleration configuration (matching /etc/nixos pattern)
      (lib.mkIf cfg.gpu.enable {
      immich-server = {
        # Ensure nvidia-container-toolkit CDI generator runs first (prevents race conditions)
        after = [ "nvidia-container-toolkit-cdi-generator.service" ];
        requires = [ "nvidia-container-toolkit-cdi-generator.service" ];

        serviceConfig = {
          # Run as eric user for simplified permissions (single-user system)
          User = lib.mkForce "eric";
          Group = lib.mkForce "users";

          # Disable user namespace isolation (conflicts with eric user ownership)
          PrivateUsers = lib.mkForce false;

          # Add GPU device access for photo/video processing
          DeviceAllow = [
            "/dev/dri/card0 rw"
            "/dev/dri/renderD128 rw"
            "/dev/nvidia0 rw"
            "/dev/nvidiactl rw"
            "/dev/nvidia-modeset rw"
            "/dev/nvidia-uvm rw"
            "/dev/nvidia-uvm-tools rw"
          ];
          # Allow access to both new uploads and external library directories
          ReadWritePaths = if cfg.storage.enable
            then [ cfg.storage.basePath ]
            else [ cfg.settings.mediaLocation ];
          ReadOnlyPaths = [ "/mnt/media/pictures" ];
          # Add user to GPU groups via supplementary groups
          SupplementaryGroups = [ "video" "render" ];

          # Allow memory locking for GPU operations (improves CUDA performance)
          LimitMEMLOCK = "infinity";

          # Higher priority for responsive media processing
          Nice = -5;
        };
        environment = {
          # ================================================================
          # CORE CONFIGURATION
          # ================================================================
          TZ = config.time.timeZone or "America/Denver";

          # ================================================================
          # MONITORING
          # ================================================================
          IMMICH_LOG_LEVEL = cfg.observability.logLevel;
        } // lib.optionalAttrs cfg.observability.metrics.enable {
          IMMICH_API_METRICS_PORT = toString cfg.observability.metrics.apiPort;
          IMMICH_MICROSERVICES_METRICS_PORT = toString cfg.observability.metrics.microservicesPort;
        } // lib.optionalAttrs (cfg.reverseProxy.trustedProxies != []) {
          # ================================================================
          # REVERSE PROXY
          # ================================================================
          # Trust reverse proxy for correct client IP logging
          IMMICH_TRUSTED_PROXIES = trustedProxiesStr;
        } // lib.optionalAttrs cfg.gpu.enable {
          # ================================================================
          # GPU ACCELERATION
          # ================================================================
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
        };
      };

      immich-machine-learning = {
        # Ensure nvidia-container-toolkit CDI generator runs first (prevents race conditions)
        after = [ "nvidia-container-toolkit-cdi-generator.service" ];
        requires = [ "nvidia-container-toolkit-cdi-generator.service" ];

        serviceConfig = {
          # Run as eric user for simplified permissions (single-user system)
          User = lib.mkForce "eric";
          Group = lib.mkForce "users";

          # Add GPU device access for ML processing
          DeviceAllow = [
            "/dev/dri/card0 rw"
            "/dev/dri/renderD128 rw"
            "/dev/nvidia0 rw"
            "/dev/nvidiactl rw"
            "/dev/nvidia-modeset rw"
            "/dev/nvidia-uvm rw"
            "/dev/nvidia-uvm-tools rw"
          ];
          # Allow ML service to read external library for analysis
          ReadOnlyPaths = [ "/mnt/media/pictures" ];
          # Add user to GPU groups via supplementary groups
          SupplementaryGroups = [ "video" "render" ];

          # Allow memory locking for GPU operations (critical for ML workloads)
          LimitMEMLOCK = "infinity";

          # Higher priority for ML inference (Smart Search, Facial Recognition)
          Nice = -10;  # Higher priority than server for responsive AI features
        };
        environment = {
          # ================================================================
          # CORE CONFIGURATION
          # ================================================================
          TZ = config.time.timeZone or "America/Denver";
        } // lib.optionalAttrs cfg.gpu.enable {
          # ================================================================
          # GPU ACCELERATION
          # ================================================================
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,utility";
          CUDA_VISIBLE_DEVICES = "0";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

          # Machine learning optimizations
          TRANSFORMERS_CACHE = "/var/lib/immich/.cache";
          MPLCONFIGDIR = "/var/lib/immich/.config/matplotlib";

          # CRITICAL: Force CUDA backend for ONNX Runtime (2-5x ML performance boost)
          # Options: "cuda" (standard) | "tensorrt" (faster, requires TensorRT)
          ONNXRUNTIME_PROVIDER = "cuda";

          # Optional: TensorRT optimization cache for even faster inference
          TENSORRT_CACHE_PATH = "/var/lib/immich/.cache/tensorrt";

          # ================================================================
          # ML PERFORMANCE TUNING
          # ================================================================
          # Keep models loaded in GPU memory longer (reduces reload overhead)
          MACHINE_LEARNING_MODEL_TTL = toString cfg.machineLearning.modelTTL;
          MACHINE_LEARNING_MODEL_TTL_POLL_S = toString cfg.machineLearning.modelTTLPollInterval;

          # Threading configuration (auto-computed from CPU cores)
          MACHINE_LEARNING_REQUEST_THREADS = toString mlRequestThreads;
          MACHINE_LEARNING_MODEL_INTER_OP_THREADS = toString mlInterOpThreads;
          MACHINE_LEARNING_MODEL_INTRA_OP_THREADS = toString mlIntraOpThreads;
        };
      };
      })
    ];

    # Open firewall port only on Tailscale interface (not public)
    # This allows HTTPS access via hwc.ocelot-wahoo.ts.net:2283 using Tailscale certs
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.settings.port ];

    #==========================================================================
    # PROMETHEUS INTEGRATION
    #==========================================================================
    # Add Immich metrics endpoints to Prometheus scraping
    hwc.server.monitoring.prometheus.scrapeConfigs = lib.mkIf (cfg.enable && cfg.observability.metrics.enable) [
      {
        job_name = "immich-api";
        static_configs = [{
          targets = [ "localhost:${toString cfg.observability.metrics.apiPort}" ];
        }];
        scrape_interval = "30s";
        scrape_timeout = "10s";
      }
      {
        job_name = "immich-workers";
        static_configs = [{
          targets = [ "localhost:${toString cfg.observability.metrics.microservicesPort}" ];
        }];
        scrape_interval = "30s";
        scrape_timeout = "10s";
      }
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (cfg.settings.mediaLocation != "");
        message = "hwc.server.immich requires mediaLocation to be set";
      }
      {
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
        message = "hwc.server.immich.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
      }
      {
        assertion = !cfg.gpu.enable || (config.hwc.infrastructure.hardware.gpu.type == "nvidia");
        message = "hwc.server.immich.gpu currently only supports NVIDIA GPUs (hwc.infrastructure.hardware.gpu.type must be 'nvidia')";
      }
      {
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.nvidia.containerRuntime;
        message = "hwc.server.immich.gpu requires hwc.infrastructure.hardware.gpu.nvidia.containerRuntime = true for nvidia-container-toolkit";
      }
      {
        assertion = !cfg.gpu.enable || (builtins.elem "nvidia" config.boot.kernelModules);
        message = "hwc.server.immich.gpu requires NVIDIA kernel modules to be loaded (check hwc.infrastructure.hardware.gpu configuration)";
      }
      {
        assertion = !cfg.storage.enable || (cfg.storage.basePath != "");
        message = "hwc.server.immich.storage requires basePath to be set";
      }
      {
        assertion = !(cfg.backup.enable && cfg.backup.includeDatabase) || config.services.postgresql.enable;
        message = "hwc.server.immich.backup.includeDatabase requires PostgreSQL to be enabled";
      }
      # Phase A assertions - metrics configuration
      {
        assertion = !cfg.observability.metrics.enable || (cfg.observability.metrics.apiPort != cfg.observability.metrics.microservicesPort);
        message = "Immich metrics ports must be different (apiPort vs microservicesPort)";
      }
      {
        assertion = !cfg.observability.metrics.enable || (cfg.observability.metrics.apiPort != cfg.settings.port);
        message = "Immich API metrics port must not conflict with main server port";
      }
      # Phase B assertions - ML performance tuning
      {
        assertion = cfg.machineLearning.cpuCores == null || cfg.machineLearning.cpuCores > 0;
        message = "Immich machineLearning.cpuCores must be positive if set (null = auto-detect)";
      }
      {
        assertion = cfg.machineLearning.modelTTL > 0;
        message = "Immich machineLearning.modelTTL must be positive (time in seconds)";
      }
      {
        assertion = cfg.machineLearning.modelTTLPollInterval > 0;
        message = "Immich machineLearning.modelTTLPollInterval must be positive (time in seconds)";
      }
      {
        assertion = cfg.machineLearning.threading.requestThreads == null || cfg.machineLearning.threading.requestThreads > 0;
        message = "Immich machineLearning.threading.requestThreads must be positive if set";
      }
      {
        assertion = cfg.machineLearning.threading.interOpThreads == null || cfg.machineLearning.threading.interOpThreads > 0;
        message = "Immich machineLearning.threading.interOpThreads must be positive if set";
      }
      {
        assertion = cfg.machineLearning.threading.intraOpThreads == null || cfg.machineLearning.threading.intraOpThreads > 0;
        message = "Immich machineLearning.threading.intraOpThreads must be positive if set";
      }
      # Phase C assertion - Prometheus integration
      {
        assertion = !(cfg.enable && cfg.observability.metrics.enable) || config.hwc.server.monitoring.prometheus.enable;
        message = "Immich metrics require Prometheus to be enabled (hwc.server.monitoring.prometheus.enable = true)";
      }
    ];

    #==========================================================================
    # WARNINGS AND NOTICES
    #==========================================================================
    warnings = lib.optional (cfg.enable && !cfg.backup.enable)
      [ "Immich backup is disabled. Your photos and database will NOT be backed up automatically!" ];
  };
}
