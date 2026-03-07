# domains/media/immich-container/index.nix
#
# Immich photo management server (containerized)
# Namespace: hwc.media.immich.*

{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.immich;
in
{
  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.immich = {
    enable = lib.mkEnableOption "Immich photo management server (containerized)";

    images = {
      server = lib.mkOption { type = lib.types.str; default = "ghcr.io/immich-app/immich-server:v2"; description = "Immich server container image"; };
      machineLearning = lib.mkOption { type = lib.types.str; default = "ghcr.io/immich-app/immich-machine-learning:v2-cuda"; description = "Immich ML container image"; };
      redis = lib.mkOption { type = lib.types.str; default = "docker.io/library/redis:7.2-alpine"; description = "Redis container image"; };
    };

    settings = {
      host = lib.mkOption { type = lib.types.str; default = "0.0.0.0"; description = "Listen address for Immich server"; };
      port = lib.mkOption { type = lib.types.port; default = 2283; description = "Port for Immich server"; };
      mediaLocation = lib.mkOption { type = lib.types.nullOr lib.types.path; default = config.hwc.paths.photos; description = "Path to media storage location"; };
    };

    storage = {
      enable = lib.mkEnableOption "Advanced storage layout with separate directories" // { default = true; };
      basePath = lib.mkOption { type = lib.types.nullOr lib.types.path; default = config.hwc.paths.photos; description = "Base path for all Immich storage"; };
      locations = {
        library = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/library" else null; description = "Primary photo/video library location"; };
        thumbs = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/thumbs" else null; description = "Thumbnail cache location"; };
        encodedVideo = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/encoded-video" else null; description = "Transcoded video storage"; };
        profile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = if config.hwc.paths.photos != null then "${config.hwc.paths.photos}/profile" else null; description = "User profile pictures"; };
      };
    };

    database = {
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "PostgreSQL host"; };
      port = lib.mkOption { type = lib.types.port; default = 5432; description = "PostgreSQL port"; };
      name = lib.mkOption { type = lib.types.str; default = "immich"; description = "Database name"; };
      user = lib.mkOption { type = lib.types.str; default = "immich"; description = "Database user"; };
      passwordFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; description = "Path to file containing database password"; };
    };

    redis = {
      enable = lib.mkEnableOption "Redis caching for Immich" // { default = true; };
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; description = "Redis host"; };
      port = lib.mkOption { type = lib.types.port; default = 6379; description = "Redis port"; };
    };

    gpu.enable = lib.mkEnableOption "GPU acceleration for photo/video processing";

    observability = {
      logLevel = lib.mkOption { type = lib.types.enum [ "verbose" "debug" "log" "warn" "error" ]; default = "log"; description = "Immich log level"; };
      metrics = {
        enable = lib.mkEnableOption "Prometheus metrics endpoints" // { default = true; };
        apiPort = lib.mkOption { type = lib.types.port; default = 8091; description = "Prometheus metrics port for immich-server"; };
        microservicesPort = lib.mkOption { type = lib.types.port; default = 8092; description = "Prometheus metrics port for ML"; };
      };
    };

    machineLearning = {
      enable = lib.mkEnableOption "Immich machine learning container" // { default = true; };
      cpuCores = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Number of CPU cores for ML threading"; };
      modelTTL = lib.mkOption { type = lib.types.int; default = 600; description = "Time-to-live for ML models in GPU memory (seconds)"; };
      modelTTLPollInterval = lib.mkOption { type = lib.types.int; default = 30; description = "How often to check if models should be unloaded (seconds)"; };
      threading = {
        requestThreads = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Concurrent ML requests to process"; };
        interOpThreads = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Inter-op parallelism for ML models"; };
        intraOpThreads = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Intra-op parallelism for ML models"; };
      };
    };

    reverseProxy.trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; description = "CIDR ranges of trusted reverse proxies"; };

    network.mode = lib.mkOption { type = lib.types.enum [ "media" "host" ]; default = "media"; description = "Network mode: media (podman network) or host"; };

    resources = {
      server = {
        memory = lib.mkOption { type = lib.types.str; default = "2g"; description = "Memory limit for immich-server"; };
        cpus = lib.mkOption { type = lib.types.str; default = "2.0"; description = "CPU limit for immich-server"; };
      };
      machineLearning = {
        memory = lib.mkOption { type = lib.types.str; default = "4g"; description = "Memory limit for immich-machine-learning"; };
        cpus = lib.mkOption { type = lib.types.str; default = "4.0"; description = "CPU limit for immich-machine-learning"; };
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable { };
}
