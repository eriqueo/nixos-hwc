# Tdarr container configuration
{ lib, config, pkgs, ... }:
let
  # Import PURE helper library
  helpers = import ../../../lib/mkContainer.nix { inherit lib pkgs; };
  inherit (helpers) mkContainer;

  cfg = config.hwc.media.tdarr;
  paths = config.hwc.paths;
  appsRoot = config.hwc.paths.apps.root;
  tdarrRoot = "${appsRoot}/tdarr";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    #=========================================================================
    # ASSERTIONS AND VALIDATION
    #=========================================================================
    {
      assertions = [
        {
          assertion = paths.hot != null && paths.media != null;
          message = "Tdarr requires hwc.paths.hot and hwc.paths.media to be configured";
        }
        {
          assertion = !cfg.gpu.enable || config.hwc.system.hardware.gpu.enable;
          message = "Tdarr GPU acceleration requires hwc.system.hardware.gpu.enable = true";
        }
      ];
    }

    #=========================================================================
    # CONTAINER CONFIGURATION
    #=========================================================================
    (mkContainer {
      name = "tdarr";
      image = cfg.image;
      networkMode = if cfg.network.mode == "vpn" then "vpn" else "media";
      gpuEnable = cfg.gpu.enable;
      gpuMode = "nvidia-cdi";  # P1000 uses CDI
      timeZone = config.time.timeZone or "America/Denver";

      # Resource limits
      memory = cfg.resources.memory;
      cpus = cfg.resources.cpus;
      memorySwap = cfg.resources.memorySwap;

      environment = {
        # Server configuration
        serverIP = "0.0.0.0";
        serverPort = toString cfg.serverPort;
        webUIPort = toString cfg.webPort;

        # FFmpeg configuration
        ffmpegVersion = cfg.ffmpegVersion;

        # Node configuration
        nodeName = "TdarrNode";
        internalNode = "true";

        # Container identification
        inContainer = "true";

        # Memory management for FFmpeg
        FFMPEG_THREAD_QUEUE_SIZE = "512";
      } // lib.optionalAttrs cfg.gpu.enable {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      };

      # Port exposure
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "127.0.0.1:${toString cfg.webPort}:${toString cfg.webPort}"
        "127.0.0.1:${toString cfg.serverPort}:${toString cfg.serverPort}"
      ];

      # Volume mounts
      volumes = [
        "${tdarrRoot}/server:/app/server"
        "${tdarrRoot}/configs:/app/configs"
        "${tdarrRoot}/logs:/app/logs"
        "${paths.media.root}/tv:/media/tv"
        "${paths.media.root}/movies:/media/movies"
        "${paths.media.root}/music:/media/music"
        "${paths.hot.root}/processing/tdarr-temp:/temp"
      ];

      dependsOn = lib.optionals (cfg.network.mode == "vpn") [ "gluetun" ];
    })

    #=========================================================================
    # SYSTEMD SERVICE DEPENDENCIES
    #=========================================================================
    {
      systemd.services.podman-tdarr = {
        after = if cfg.network.mode == "vpn"
          then [ "podman-gluetun.service" ]
          else [ "init-media-network.service" ];
        wants = if cfg.network.mode == "vpn"
          then [ "podman-gluetun.service" ]
          else [ "init-media-network.service" ];

        preStart = ''
          install -d -m755 ${paths.hot.root}/processing/tdarr-temp
          chown -R 1000:1000 ${paths.hot.root}/processing/tdarr-temp
        '';
      };
    }

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    {
      networking.firewall.allowedTCPPorts = lib.optionals (cfg.network.mode != "vpn") [
        cfg.webPort
        cfg.serverPort
      ];
    }
  ]);
}
