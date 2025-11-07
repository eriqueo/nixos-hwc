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
      mediaLocation = cfg.settings.mediaLocation;
      database = {
        createDB = cfg.database.createDB;
        name = cfg.database.name;
        user = cfg.database.user;
      };
      redis.enable = cfg.redis.enable;
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
          ReadWritePaths = [ cfg.settings.mediaLocation ];
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
    ];
  };
}