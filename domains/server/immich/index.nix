{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.immich;
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
      mediaLocation = if cfg.storage.enable
        then cfg.storage.locations.library
        else cfg.settings.mediaLocation;
      database = {
        createDB = cfg.database.createDB;
        name = cfg.database.name;
        user = cfg.database.user;
      };
      redis.enable = cfg.redis.enable;

      # Configure separate storage locations via environment variables
      environment = lib.mkIf cfg.storage.enable {
        UPLOAD_LOCATION = cfg.storage.locations.library;
        THUMB_LOCATION = cfg.storage.locations.thumbs;
        ENCODED_VIDEO_LOCATION = cfg.storage.locations.encodedVideo;
        PROFILE_LOCATION = cfg.storage.locations.profile;
      };
    };

    # Create storage directories
    systemd.tmpfiles.rules = lib.mkIf cfg.storage.enable [
      "d ${cfg.storage.basePath} 0750 immich immich -"
      "d ${cfg.storage.locations.library} 0750 immich immich -"
      "d ${cfg.storage.locations.thumbs} 0750 immich immich -"
      "d ${cfg.storage.locations.encodedVideo} 0750 immich immich -"
      "d ${cfg.storage.locations.profile} 0750 immich immich -"
      "d ${cfg.backup.databaseBackupPath} 0750 postgres postgres -"
    ];

    # PostgreSQL database backup service
    services.postgresqlBackup = lib.mkIf (cfg.backup.enable && cfg.backup.includeDatabase) {
      enable = true;
      databases = [ cfg.database.name ];
      location = cfg.backup.databaseBackupPath;
      startAt = if cfg.backup.schedule == "hourly" then "hourly" else "*-*-* 02:00:00";
      compression = "zstd";
    };

    # GPU acceleration configuration (matching /etc/nixos pattern)
    systemd.services = lib.mkIf cfg.gpu.enable {
      immich-server = {
        serviceConfig = {
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
        };
        environment = {
          # NVIDIA GPU acceleration for transcoding/thumbnail generation
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
        };
      };

      immich-machine-learning = {
        serviceConfig = {
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
        };
        environment = {
          # NVIDIA GPU acceleration for ML workloads (CLIP, facial recognition)
          NVIDIA_VISIBLE_DEVICES = "0";
          NVIDIA_DRIVER_CAPABILITIES = "compute,utility";
          CUDA_VISIBLE_DEVICES = "0";
          LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

          # Machine learning optimizations
          TRANSFORMERS_CACHE = "/var/lib/immich/.cache";
          MPLCONFIGDIR = "/var/lib/immich/.config/matplotlib";
        };
      };
    };

    # Open firewall port only on Tailscale interface (not public)
    # This allows HTTPS access via hwc.ocelot-wahoo.ts.net:2283 using Tailscale certs
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.settings.port ];

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
        assertion = !cfg.storage.enable || (cfg.storage.basePath != "");
        message = "hwc.server.immich.storage requires basePath to be set";
      }
      {
        assertion = !(cfg.backup.enable && cfg.backup.includeDatabase) || config.services.postgresql.enable;
        message = "hwc.server.immich.backup.includeDatabase requires PostgreSQL to be enabled";
      }
    ];

    #==========================================================================
    # WARNINGS AND NOTICES
    #==========================================================================
    warnings = lib.optional (cfg.enable && !cfg.backup.enable)
      "Immich backup is disabled. Your photos and database will NOT be backed up automatically!";
  };
}