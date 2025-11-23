# domains/server/frigate-v2/options.nix
#
# Frigate NVR (Config-First Pattern) - Infrastructure Options Only
# Charter v7.0 Section 19 compliant
#
# NAMESPACE: hwc.server.frigate-v2.*
#
# PHILOSOPHY:
#   Nix handles: image, ports, GPU, volumes, env
#   Config file handles: cameras, detectors, recording, zones, etc.
#
{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.frigate-v2 = {
    enable = mkEnableOption "Frigate NVR (config-first pattern)";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt";
      description = ''
        Container image for Frigate NVR.
        Uses -tensorrt variant which includes CUDA support for ONNX detector.

        Note: Despite the name, this image supports both TensorRT AND ONNX with CUDA.
        The base 0.16.2 image only has OpenVINO (Intel) + CPU, no CUDA support.

        For NVIDIA GPUs with ONNX detector, you MUST use the -tensorrt variant.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Web UI port";
    };

    gpu = {
      enable = mkEnableOption "GPU acceleration for object detection";

      device = mkOption {
        type = types.int;
        default = 0;
        description = "GPU device number (NVIDIA)";
      };
    };

    storage = {
      configPath = mkOption {
        type = types.str;
        default = "/opt/surveillance/frigate/config";
        description = "Configuration directory path (mounts config.yml)";
      };

      mediaPath = mkOption {
        type = types.str;
        default = "/mnt/media/surveillance/frigate/media";
        description = "Media storage path (recordings)";
      };

      bufferPath = mkOption {
        type = types.str;
        default = "/mnt/hot/surveillance/buffer";
        description = "Buffer storage path (hot storage for temporary files)";
      };
    };

    resources = {
      memory = mkOption {
        type = types.str;
        default = "4g";
        description = "Container memory limit";
      };

      cpus = mkOption {
        type = types.str;
        default = "1.5";
        description = "Container CPU limit";
      };

      shmSize = mkOption {
        type = types.str;
        default = "1g";
        description = "Shared memory size";
      };
    };

    firewall = {
      tailscaleOnly = mkOption {
        type = types.bool;
        default = true;
        description = "Restrict access to Tailscale interface only";
      };
    };
  };
}
