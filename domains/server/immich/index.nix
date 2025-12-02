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
# - Run: workspace/utilities/immich-gpu-check.sh
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

    # Create storage directories
    systemd.tmpfiles.rules =
      (if cfg.storage.enable then [
        "d ${cfg.storage.basePath} 0750 immich immich -"
        "d ${cfg.storage.locations.library} 0750 immich immich -"
        "d ${cfg.storage.locations.thumbs} 0750 immich immich -"
        "d ${cfg.storage.locations.encodedVideo} 0750 immich immich -"
        "d ${cfg.storage.locations.profile} 0750 immich immich -"
        "d ${cfg.backup.databaseBackupPath} 0750 postgres postgres -"
        # Create .immich marker files for mount verification
        "f ${cfg.storage.locations.library}/.immich 0600 immich immich -"
        "f ${cfg.storage.locations.thumbs}/.immich 0600 immich immich -"
        "f ${cfg.storage.locations.encodedVideo}/.immich 0600 immich immich -"
        "f ${cfg.storage.locations.profile}/.immich 0600 immich immich -"
      ] else []) ++ (if cfg.gpu.enable then [
        # GPU cache directories for ML optimizations
        "d /var/lib/immich/.cache 0750 immich immich -"
        "d /var/lib/immich/.cache/tensorrt 0750 immich immich -"
        "d /var/lib/immich/.config 0750 immich immich -"
        "d /var/lib/immich/.config/matplotlib 0750 immich immich -"
      ] else []);

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
        # Ensure nvidia-container-toolkit CDI generator runs first (prevents race conditions)
        after = [ "nvidia-container-toolkit-cdi-generator.service" ];
        requires = [ "nvidia-container-toolkit-cdi-generator.service" ];

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

          # Allow memory locking for GPU operations (improves CUDA performance)
          LimitMEMLOCK = "infinity";

          # Higher priority for responsive media processing
          Nice = -5;
        };
        environment = {
          # NVIDIA GPU acceleration for transcoding/thumbnail generation
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
          # NVIDIA GPU acceleration for ML workloads (CLIP, facial recognition)
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
    ];

    #==========================================================================
    # WARNINGS AND NOTICES
    #==========================================================================
    warnings = lib.optional (cfg.enable && !cfg.backup.enable)
      [ "Immich backup is disabled. Your photos and database will NOT be backed up automatically!" ];
  };
}
