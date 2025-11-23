# domains/server/frigate-v2/index.nix
#
# Frigate NVR - Config-First Pattern
# Charter v7.0 Section 19 compliant
#
# NAMESPACE: hwc.server.frigate-v2.*
#
# ARCHITECTURE:
#   - Nix: Container infrastructure (image, GPU, volumes, ports)
#   - YAML: Frigate configuration (cameras, detectors, recording)
#   - Config file: domains/server/frigate-v2/config/config.yml
#
# DEPENDENCIES:
#   - hwc.infrastructure.hardware.gpu (for GPU acceleration)
#   - hwc.secrets (for RTSP credentials)
#   - virtualisation.oci-containers.backend = "podman"
#
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.frigate-v2;

  # Path to canonical config file (version-controlled)
  configFile = ./config/config.yml;

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    # Frigate container
    virtualisation.oci-containers.containers.frigate-v2 = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--network=host"
        "--security-opt=label=disable"
        "--privileged"
        "--tmpfs=/tmp/cache:size=1g"
        "--shm-size=${cfg.resources.shmSize}"
        "--memory=${cfg.resources.memory}"
        "--cpus=${cfg.resources.cpus}"
      ]
      # NVIDIA GPU device passthrough (for object detection)
      ++ lib.optionals cfg.gpu.enable [
        "--device=nvidia.com/gpu=${toString cfg.gpu.device}"
      ];

      environment = {
        TZ = "America/Denver";
      } // lib.optionalAttrs cfg.gpu.enable {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
        CUDA_VISIBLE_DEVICES = toString cfg.gpu.device;
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
      };

      volumes = [
        # CANONICAL CONFIG FILE (from repo, version-controlled)
        "${configFile}:/config/config.yml:ro"

        # Model cache (ONNX model file goes here)
        "${cfg.storage.configPath}/models:/config/models:ro"

        # Labelmap (coco-80.txt)
        "${cfg.storage.configPath}/labelmap:/labelmap:ro"

        # Storage
        "${cfg.storage.mediaPath}:/media/frigate"
        "${cfg.storage.bufferPath}:/tmp/frigate"

        # System time
        "/etc/localtime:/etc/localtime:ro"
      ];
    };

    # Firewall rules
    networking.firewall = {
      # Always allow localhost for reverse proxy
      interfaces."lo".allowedTCPPorts = [ cfg.port ];

      # Optionally restrict external access to Tailscale only
      interfaces."tailscale0" = lib.mkIf cfg.firewall.tailscaleOnly {
        allowedTCPPorts = [ cfg.port 8554 8555 ];
        allowedUDPPorts = [ 8555 ];
      };
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = [
    {
      assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
      message = "hwc.server.frigate-v2.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
    }
    {
      assertion = !cfg.enable || (cfg.storage.mediaPath != "");
      message = "hwc.server.frigate-v2.storage.mediaPath must be set";
    }
    {
      assertion = !cfg.enable || (cfg.storage.bufferPath != "");
      message = "hwc.server.frigate-v2.storage.bufferPath must be set";
    }
    {
      assertion = !cfg.enable || config.hwc.secrets.enable;
      message = "hwc.server.frigate-v2 requires hwc.secrets.enable = true for RTSP credentials";
    }
    {
      assertion = !cfg.enable || (config.virtualisation.oci-containers.backend == "podman");
      message = "hwc.server.frigate-v2 requires Podman as OCI container backend";
    }
    {
      assertion = !cfg.enable || builtins.pathExists configFile;
      message = "hwc.server.frigate-v2 requires config/config.yml to exist";
    }
  ];
}
