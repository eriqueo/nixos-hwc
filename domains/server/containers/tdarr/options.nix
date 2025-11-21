# modules/server/containers/tdarr/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.tdarr = {
    enable = mkEnableOption "Tdarr video transcoding container";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/haveagitgat/tdarr:latest";
      description = "Container image for Tdarr server";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode: 'media' for direct access, 'vpn' to route through gluetun";
    };

    webPort = mkOption {
      type = types.port;
      default = 8265;
      description = "Web UI port";
    };

    serverPort = mkOption {
      type = types.port;
      default = 8266;
      description = "Server communication port";
    };

    gpu.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable NVIDIA GPU acceleration for transcoding (NVENC/NVDEC)";
    };

    workers = mkOption {
      type = types.int;
      default = 1;
      description = "Number of worker nodes (typically 1 for single-server setup)";
    };

    ffmpegVersion = mkOption {
      type = types.enum [ "6" "7" ];
      default = "6";
      description = "FFmpeg version to use";
    };

    resources = {
      memory = mkOption {
        type = types.str;
        default = "12g";
        description = ''
          Memory limit for the container.
          Transcoding large/4K files requires significant RAM.
          Recommended: 12g minimum, 16g for 4K content.
        '';
      };

      memorySwap = mkOption {
        type = types.str;
        default = "16g";
        description = ''
          Total memory limit (memory + swap).
          Should be at least 4g more than memory limit.
        '';
      };

      cpus = mkOption {
        type = types.str;
        default = "4.0";
        description = ''
          CPU limit (number of cores).
          More CPUs help with non-GPU encode steps and parallel processing.
        '';
      };
    };
  };
}
