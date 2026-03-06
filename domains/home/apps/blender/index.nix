# domains/home/apps/blender/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.blender;

  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};
  gpuCfg = osCfg.hwc.system.hardware.gpu or { type = "none"; enable = false; };

  blenderPackage = pkgs.blender.override {
    cudaSupport = cfg.cudaSupport && (gpuCfg.type == "nvidia");
    rocmSupport = cfg.rocmSupport && (gpuCfg.type == "amd");
  };

  blenderGpuWrapper = pkgs.writeShellScriptBin "blender-gpu" ''
    #!/usr/bin/env bash
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec ${blenderPackage}/bin/blender "$@"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.blender = {
    enable = lib.mkEnableOption "Blender 3D creation suite";

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable CUDA GPU rendering support (NVIDIA).";
    };

    rocmSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable ROCm/HIP support for GPU rendering (AMD).";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install regular Blender (binary-cached, no rebuild!)
    home.packages = [
      blenderPackage
    ] ++ lib.optionals (cfg.cudaSupport && gpuCfg.type == "nvidia") [
      # Add GPU wrapper for convenient GPU-enabled launches
      blenderGpuWrapper
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # GPU hardware validation (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where GPU config is available
      # On non-NixOS hosts, user is responsible for GPU driver setup
      {
        assertion = !cfg.cudaSupport || !isNixOSHost || (gpuCfg.enable && gpuCfg.type == "nvidia");
        message = "Blender CUDA support requires hwc.system.hardware.gpu.type = \"nvidia\" and GPU to be enabled";
      }
      {
        assertion = !cfg.rocmSupport || !isNixOSHost || (gpuCfg.enable && gpuCfg.type == "amd");
        message = "Blender ROCm support requires hwc.system.hardware.gpu.type = \"amd\" and GPU to be enabled";
      }
    ];
  };
}
