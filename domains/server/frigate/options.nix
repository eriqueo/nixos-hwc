# domains/server/frigate/options.nix
#
# Frigate NVR Options
# Charter v6.0 compliant option declarations
{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.frigate = {
    enable = mkEnableOption "Frigate NVR container service";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/blakeblackshear/frigate:stable-tensorrt";
      description = "Container image for Frigate NVR";
    };

    settings = {
      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host binding for container";
      };

      port = mkOption {
        type = types.port;
        default = 5000;
        description = "Web UI port";
      };

      timezone = mkOption {
        type = types.str;
        default = "America/Denver";
        description = "UI timezone";
      };
    };

    storage = {
      configPath = mkOption {
        type = types.str;
        default = "/opt/surveillance/frigate/config";
        description = "Configuration directory path";
      };

      mediaPath = mkOption {
        type = types.str;
        default = "/mnt/media/surveillance/frigate/media";
        description = "Media storage path (cold storage)";
      };

      bufferPath = mkOption {
        type = types.str;
        default = "/mnt/hot/surveillance/buffer";
        description = "Buffer storage path (hot storage)";
      };

      maxSizeGB = mkOption {
        type = types.int;
        default = 2000;
        description = "Maximum storage size in GB";
      };

      pruneSchedule = mkOption {
        type = types.str;
        default = "hourly";
        description = "Storage pruning schedule";
      };
    };

    gpu = {
      enable = mkEnableOption "GPU acceleration for object detection";

      device = mkOption {
        type = types.int;
        default = 0;
        description = "GPU device number";
      };

      detector = mkOption {
        type = types.enum [ "tensorrt" "cpu" "onnx" ];
        default = "cpu";
        description = "Detector type";
      };

      useFP16 = mkOption {
        type = types.bool;
        default = false;
        description = "Use FP16 precision (disable for Pascal GPUs)";
      };
    };

    mqtt = {
      enable = mkEnableOption "MQTT broker for event communication";

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "MQTT broker host";
      };

      port = mkOption {
        type = types.port;
        default = 1883;
        description = "MQTT broker port";
      };
    };

    monitoring = {
      watchdog = {
        enable = mkEnableOption "Camera health monitoring";

        schedule = mkOption {
          type = types.str;
          default = "*:0/30";
          description = "Health check interval";
        };
      };

      prometheus = {
        enable = mkEnableOption "Prometheus metrics export";

        textfilePath = mkOption {
          type = types.str;
          default = "/var/lib/node-exporter-textfile";
          description = "Prometheus textfile collector path";
        };
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

    reverseProxy = {
      enable = mkEnableOption "Enable reverse proxy route for Frigate";

      path = mkOption {
        type = types.str;
        default = "/frigate";
        description = "URL path for reverse proxy";
      };
    };

    firewall = {
      tailscaleOnly = mkOption {
        type = types.bool;
        default = true;
        description = "Restrict to Tailscale interface";
      };
    };
  };
}
