# Tdarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.tdarr;
  paths = config.hwc.paths;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    assertions = [
      {
        assertion = paths.hot != null && paths.media != null;
        message = "Tdarr requires hwc.paths.hot and hwc.paths.media to be configured";
      }
      {
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
        message = "Tdarr GPU acceleration requires hwc.infrastructure.hardware.gpu.enable = true";
      }
    ];

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    virtualisation.oci-containers.containers.tdarr = {
      image = cfg.image;
      autoStart = true;

      # Network configuration
      extraOptions = [
        "--memory=${cfg.resources.memory}"
        "--cpus=${cfg.resources.cpus}"
        "--memory-swap=${cfg.resources.memorySwap}"
      ] ++ (
        if cfg.network.mode == "vpn"
        then [ "--network=container:gluetun" ]
        else [ "--network=media-network" ]
      ) ++ lib.optionals cfg.gpu.enable [
        # NVIDIA GPU passthrough (P1000 supports NVENC/NVDEC)
        # Use CDI (Container Device Interface) with nvidia-container-toolkit
        "--device=nvidia.com/gpu=0"
      ];

      # Environment variables
      environment = {
        PUID = "1000";
        PGID = "100"  # users GID;
        TZ = config.time.timeZone or "America/Denver";

        # Server configuration
        serverIP = "0.0.0.0";
        serverPort = toString cfg.serverPort;
        webUIPort = toString cfg.webPort;

        # FFmpeg configuration
        ffmpegVersion = cfg.ffmpegVersion;

        # Node configuration
        nodeName = "TdarrNode";
        internalNode = "true";  # Enable worker node in same container

        # SAFETY SETTINGS - Prevent file deletion/corruption
        # Keep original files until transcode is verified
        inContainer = "true";

        # Memory management for FFmpeg
        # These help prevent OOM issues during large file transcoding
        FFMPEG_THREAD_QUEUE_SIZE = "512";  # Reduce memory usage per stream

        # GPU configuration (NVIDIA)
      } // lib.optionalAttrs cfg.gpu.enable {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      };

      # Port exposure
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "127.0.0.1:${toString cfg.webPort}:${toString cfg.webPort}"    # Web UI
        "127.0.0.1:${toString cfg.serverPort}:${toString cfg.serverPort}"  # Server
      ];

      # Volume mounts
      volumes = [
        # Config and database
        "/opt/downloads/tdarr/server:/app/server"
        "/opt/downloads/tdarr/configs:/app/configs"
        "/opt/downloads/tdarr/logs:/app/logs"

        # Media libraries (read/write for transcoding)
        "${paths.media}/tv:/media/tv"
        "${paths.media}/movies:/media/movies"
        "${paths.media}/music:/media/music"

        # Transcode cache (hot storage for speed)
        "${paths.hot}/processing/tdarr-temp:/temp"
      ];

      # Dependencies
      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    };

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    systemd.services.podman-tdarr = {
      after = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "init-media-network.service" ];
      wants = if cfg.network.mode == "vpn"
        then [ "podman-gluetun.service" ]
        else [ "init-media-network.service" ];

      # Ensure tdarr-temp directory exists
      preStart = ''
        install -d -m755 ${paths.hot}/processing/tdarr-temp
        chown -R 1000:1000 ${paths.hot}/processing/tdarr-temp
      '';
    };

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    networking.firewall.allowedTCPPorts = lib.optionals (cfg.network.mode != "vpn") [
      cfg.webPort
      cfg.serverPort
    ];
  };
}
