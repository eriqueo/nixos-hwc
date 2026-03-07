{ lib, config, pkgs, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.tdarr = {
    enable = lib.mkEnableOption "Tdarr video transcoding container";
    image = lib.mkOption { type = lib.types.str; default = "ghcr.io/haveagitgat/tdarr:2.26.01"; description = "Container image for Tdarr server"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    webPort = lib.mkOption { type = lib.types.port; default = 8265; description = "Web UI port"; };
    serverPort = lib.mkOption { type = lib.types.port; default = 8266; description = "Server communication port"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; description = "Enable NVIDIA GPU acceleration for transcoding"; };
    workers = lib.mkOption { type = lib.types.int; default = 1; description = "Number of worker nodes"; };
    ffmpegVersion = lib.mkOption { type = lib.types.enum [ "6" "7" ]; default = "7"; description = "FFmpeg version to use"; };
    resources = {
      memory = lib.mkOption { type = lib.types.str; default = "12g"; description = "Memory limit for the container"; };
      memorySwap = lib.mkOption { type = lib.types.str; default = "16g"; description = "Total memory limit (memory + swap)"; };
      cpus = lib.mkOption { type = lib.types.str; default = "4.0"; description = "CPU limit (number of cores)"; };
    };
  };

  imports = [
    ./parts/config.nix
    ./parts/setup.nix
    ./parts/safety.nix
  ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

  #==========================================================================
  # VALIDATION
  #==========================================================================
    config.assertions = lib.mkIf (config ? enable && config.enable) [];

}
