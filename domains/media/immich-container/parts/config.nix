# Immich Container Configuration
# Carbon copy of native immich service translated to containers
{ lib, config, pkgs, ... }:
let
  # Import PURE helper library
  helpers = import ../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;

  cfg = config.hwc.media.immich;
  paths = config.hwc.paths;
  appsRoot = config.hwc.paths.apps.root;
  immichRoot = "${appsRoot}/immich";
  immichCacheRoot = "${immichRoot}/cache";
  immichConfigRoot = "${immichRoot}/config";
  immichModelCache = "${immichRoot}/model-cache";
  immichRedis = "${immichRoot}/redis";

  # Auto-detect CPU cores from /proc/cpuinfo or use configured value
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

  # Database URL for containers
  dbUrl = "postgresql://${cfg.database.user}@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}";

  # Redis URL for containers
  redisUrl = "redis://${cfg.redis.host}:${toString cfg.redis.port}";

in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    #=========================================================================
    # STORAGE DIRECTORIES
    #=========================================================================
    {
      systemd.tmpfiles.rules =
        (if cfg.storage.enable then [
          "z ${cfg.storage.basePath} 0755 eric users -"
          "d ${cfg.storage.locations.library} 0750 eric users -"
          "d ${cfg.storage.locations.thumbs} 0750 eric users -"
          "d ${cfg.storage.locations.encodedVideo} 0750 eric users -"
          "d ${cfg.storage.locations.profile} 0750 eric users -"
          "f ${cfg.storage.locations.library}/.immich 0600 eric users -"
          "f ${cfg.storage.locations.thumbs}/.immich 0600 eric users -"
          "f ${cfg.storage.locations.encodedVideo}/.immich 0600 eric users -"
          "f ${cfg.storage.locations.profile}/.immich 0600 eric users -"
        ] else []) ++ (if cfg.gpu.enable then [
          "d ${immichCacheRoot} 0750 eric users -"
          "d ${immichCacheRoot}/tensorrt 0750 eric users -"
          "d ${immichConfigRoot} 0750 eric users -"
          "d ${immichConfigRoot}/matplotlib 0750 eric users -"
        ] else []) ++ [
          "d ${immichModelCache} 0750 eric users -"
          "d ${immichRedis} 0750 eric users -"
        ];
    }

    #=========================================================================
    # POSTGRESQL DATABASE SETUP
    #=========================================================================
    {
      systemd.services.postgresql.postStart = lib.mkAfter ''
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

    #=========================================================================
    # REDIS CONTAINER
    #=========================================================================
    (lib.mkIf cfg.redis.enable (mkContainer {
      name = "immich-redis";
      image = cfg.images.redis;
      networkMode = if cfg.network.mode == "media" then "media" else "host";
      gpuEnable = false;
      timeZone = config.time.timeZone or "America/Denver";

      # Resource limits
      memory = "512m";
      cpus = "0.5";
      memorySwap = "1g";

      # Run as eric:users for BGSAVE
      user = "1000:100";

      # Extra options for network alias
      extraOptions = lib.optionals (cfg.network.mode != "host") [
        "--network-alias=immich-redis"
      ];

      volumes = [
        "${immichRedis}:/data:rw"
      ];

      cmd = [ "redis-server" "--port" (toString cfg.redis.port) "--save" "60" "1" "--loglevel" "warning" ];
    }))

    #=========================================================================
    # IMMICH SERVER CONTAINER
    #=========================================================================
    (mkContainer {
      name = "immich-server";
      image = cfg.images.server;
      networkMode = if cfg.network.mode == "media" then "media" else "host";
      gpuEnable = cfg.gpu.enable;
      gpuMode = "nvidia-cdi";
      timeZone = config.time.timeZone or "America/Denver";

      # Resource limits
      memory = cfg.resources.server.memory;
      cpus = cfg.resources.server.cpus;
      memorySwap = "4g";

      # Extra options for network alias
      extraOptions = lib.optionals (cfg.network.mode != "host") [
        "--network-alias=immich-server"
      ];

      ports = lib.optionals (cfg.network.mode != "host") [
        "127.0.0.1:${toString cfg.settings.port}:3001"
      ];

      environment = {
        IMMICH_PORT = toString cfg.settings.port;
        DB_URL = dbUrl;
        DB_HOSTNAME = cfg.database.host;
        DB_PORT = toString cfg.database.port;
        DB_DATABASE_NAME = cfg.database.name;
        DB_USERNAME = cfg.database.user;
        REDIS_HOSTNAME = cfg.redis.host;
        REDIS_PORT = toString cfg.redis.port;
        IMMICH_MACHINE_LEARNING_URL = "http://localhost:3003";
        UPLOAD_LOCATION = if cfg.storage.enable
          then cfg.storage.basePath
          else cfg.settings.mediaLocation;
        IMMICH_LOG_LEVEL = cfg.observability.logLevel;
      } // lib.optionalAttrs cfg.storage.enable {
        THUMB_LOCATION = cfg.storage.locations.thumbs;
        ENCODED_VIDEO_LOCATION = cfg.storage.locations.encodedVideo;
        PROFILE_LOCATION = cfg.storage.locations.profile;
      } // lib.optionalAttrs cfg.observability.metrics.enable {
        IMMICH_API_METRICS_PORT = toString cfg.observability.metrics.apiPort;
        IMMICH_MICROSERVICES_METRICS_PORT = toString cfg.observability.metrics.microservicesPort;
      } // lib.optionalAttrs (cfg.reverseProxy.trustedProxies != []) {
        IMMICH_TRUSTED_PROXIES = trustedProxiesStr;
      } // lib.optionalAttrs cfg.gpu.enable {
        NVIDIA_VISIBLE_DEVICES = "0";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      };

      volumes = [
        "${cfg.storage.basePath}:/usr/src/app/upload:rw"
      ] ++ lib.optionals cfg.storage.enable [
        "${cfg.storage.locations.library}:/usr/src/app/upload/library:rw"
        "${cfg.storage.locations.thumbs}:/usr/src/app/upload/thumbs:rw"
        "${cfg.storage.locations.encodedVideo}:/usr/src/app/upload/encoded-video:rw"
        "${cfg.storage.locations.profile}:/usr/src/app/upload/profile:rw"
      ] ++ [
        "${config.hwc.paths.media.root}/pictures:/mnt/media/pictures:ro"
        "${config.hwc.paths.photos}/archive:/mnt/media/photos/archive:ro"
      ];

      dependsOn = lib.optionals cfg.redis.enable [ "immich-redis" ];
    })

    #=========================================================================
    # IMMICH MACHINE LEARNING CONTAINER
    #=========================================================================
    (lib.mkIf cfg.machineLearning.enable (mkContainer {
      name = "immich-machine-learning";
      image = cfg.images.machineLearning;
      networkMode = if cfg.network.mode == "media" then "media" else "host";
      gpuEnable = cfg.gpu.enable;
      gpuMode = "nvidia-cdi";
      timeZone = config.time.timeZone or "America/Denver";

      # Resource limits
      memory = cfg.resources.machineLearning.memory;
      cpus = cfg.resources.machineLearning.cpus;
      memorySwap = "8g";

      # Extra options for network alias
      extraOptions = lib.optionals (cfg.network.mode != "host") [
        "--network-alias=immich-machine-learning"
      ];

      environment = {
        DB_URL = dbUrl;
        REDIS_HOSTNAME = cfg.redis.host;
        REDIS_PORT = toString cfg.redis.port;
      } // lib.optionalAttrs cfg.gpu.enable {
        NVIDIA_VISIBLE_DEVICES = "0";
        NVIDIA_DRIVER_CAPABILITIES = "compute,utility";
        CUDA_VISIBLE_DEVICES = "0";
        TRANSFORMERS_CACHE = "/cache";
        MPLCONFIGDIR = "/cache/matplotlib";
        ONNXRUNTIME_PROVIDER = "cuda";
        TENSORRT_CACHE_PATH = "/cache/tensorrt";
        MACHINE_LEARNING_MODEL_TTL = toString cfg.machineLearning.modelTTL;
        MACHINE_LEARNING_MODEL_TTL_POLL_S = toString cfg.machineLearning.modelTTLPollInterval;
        MACHINE_LEARNING_REQUEST_THREADS = toString mlRequestThreads;
        MACHINE_LEARNING_MODEL_INTER_OP_THREADS = toString mlInterOpThreads;
        MACHINE_LEARNING_MODEL_INTRA_OP_THREADS = toString mlIntraOpThreads;
      };

      volumes = [
        "${config.hwc.paths.media.root}/pictures:/mnt/media/pictures:ro"
      ] ++ (if cfg.gpu.enable then [
        "${immichCacheRoot}:/cache:rw"
        "${immichCacheRoot}/tensorrt:/cache/tensorrt:rw"
        "${immichConfigRoot}/matplotlib:/cache/matplotlib:rw"
      ] else [
        "${immichModelCache}:/cache:rw"
      ]);

      dependsOn = lib.optionals cfg.redis.enable [ "immich-redis" ];
    }))

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    {
      systemd.services = {
        "podman-immich-server" = {
          after = [ "network-online.target" "postgresql.service" ]
            ++ lib.optional cfg.redis.enable "podman-immich-redis.service"
            ++ lib.optional (cfg.network.mode == "media") "init-media-network.service"
            ++ lib.optional cfg.gpu.enable "nvidia-container-toolkit-cdi-generator.service";
          requires = lib.optional cfg.gpu.enable "nvidia-container-toolkit-cdi-generator.service";
          wants = [ "network-online.target" ];
        };

        "podman-immich-machine-learning" = lib.mkIf cfg.machineLearning.enable {
          after = [ "network-online.target" "postgresql.service" "podman-immich-server.service" ]
            ++ lib.optional cfg.redis.enable "podman-immich-redis.service"
            ++ lib.optional (cfg.network.mode == "media") "init-media-network.service"
            ++ lib.optional cfg.gpu.enable "nvidia-container-toolkit-cdi-generator.service";
          requires = lib.optional cfg.gpu.enable "nvidia-container-toolkit-cdi-generator.service";
          wants = [ "network-online.target" ];
        };

        "podman-immich-redis" = lib.mkIf cfg.redis.enable {
          after = [ "network-online.target" ]
            ++ lib.optional (cfg.network.mode == "media") "init-media-network.service";
          wants = [ "network-online.target" ];
        };
      };
    }

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    {
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.settings.port ];
    }

    #=========================================================================
    # PROMETHEUS INTEGRATION
    #=========================================================================
    (lib.mkIf cfg.observability.metrics.enable {
      hwc.monitoring.prometheus.scrapeConfigs = [
        {
          job_name = "immich-api";
          static_configs = [{
            targets = [ "localhost:${toString cfg.observability.metrics.apiPort}" ];
          }];
          scrape_interval = "30s";
          scrape_timeout = "10s";
        }
      ] ++ lib.optionals cfg.machineLearning.enable [
        {
          job_name = "immich-workers";
          static_configs = [{
            targets = [ "localhost:${toString cfg.observability.metrics.microservicesPort}" ];
          }];
          scrape_interval = "30s";
          scrape_timeout = "10s";
        }
      ];
    })

    #=========================================================================
    # VALIDATION
    #=========================================================================
    {
      assertions = [
        {
          assertion = !cfg.enable || (cfg.settings.mediaLocation != null);
          message = "hwc.media.immich requires mediaLocation to be set";
        }
        {
          assertion = !cfg.gpu.enable || config.hwc.system.hardware.gpu.enable;
          message = "hwc.media.immich.gpu requires hwc.system.hardware.gpu.enable = true";
        }
        {
          assertion = !cfg.gpu.enable || (config.hwc.system.hardware.gpu.type == "nvidia");
          message = "hwc.media.immich.gpu currently only supports NVIDIA GPUs (hwc.system.hardware.gpu.type must be 'nvidia')";
        }
        {
          assertion = !cfg.gpu.enable || config.hwc.system.hardware.gpu.nvidia.containerRuntime;
          message = "hwc.media.immich.gpu requires hwc.system.hardware.gpu.nvidia.containerRuntime = true for nvidia-container-toolkit";
        }
        {
          assertion = !cfg.gpu.enable || (builtins.elem "nvidia" config.boot.kernelModules);
          message = "hwc.media.immich.gpu requires NVIDIA kernel modules to be loaded (check hwc.system.hardware.gpu configuration)";
        }
        {
          assertion = !cfg.storage.enable || (cfg.storage.basePath != null);
          message = "hwc.media.immich.storage requires basePath to be set";
        }
        {
          assertion = !cfg.observability.metrics.enable || (cfg.observability.metrics.apiPort != cfg.observability.metrics.microservicesPort);
          message = "Immich metrics ports must be different (apiPort vs microservicesPort)";
        }
        {
          assertion = !cfg.observability.metrics.enable || (cfg.observability.metrics.apiPort != cfg.settings.port);
          message = "Immich API metrics port must not conflict with main server port";
        }
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
          assertion = !(cfg.enable && cfg.observability.metrics.enable) || config.hwc.monitoring.prometheus.enable;
          message = "Immich metrics require Prometheus to be enabled (hwc.monitoring.prometheus.enable = true)";
        }
      ];
    }
  ]);
}
