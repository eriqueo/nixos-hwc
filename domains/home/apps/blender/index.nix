{ config, lib, pkgs, osConfig ? {}, ... }:

let
  enabled = config.hwc.home.apps.blender.enable or false;
  cfg = config.hwc.home.apps.blender;

  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;

  # Access system GPU config via osConfig (available in Home Manager)
  gpuCfg = osConfig.hwc.infrastructure.hardware.gpu or { type = "none"; enable = false; };

  # Build Blender with CUDA support for Cycles GPU rendering
  blenderPackage = pkgs.blender.override {
    cudaSupport = cfg.cudaSupport && (gpuCfg.type == "nvidia");
    hipSupport = cfg.hipSupport && (gpuCfg.type == "amd");
  };

  # Create a GPU-enabled wrapper for NVIDIA systems
  # Note: The system already provides blender-offload script in gpu.nix
  blenderGpuWrapper = pkgs.writeShellScriptBin "blender-gpu" ''
    #!/usr/bin/env bash
    # Launch Blender with NVIDIA GPU offload enabled
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
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
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
        message = "Blender CUDA support requires hwc.infrastructure.hardware.gpu.type = \"nvidia\" and GPU to be enabled";
      }
      {
        assertion = !cfg.hipSupport || !isNixOSHost || (gpuCfg.enable && gpuCfg.type == "amd");
        message = "Blender HIP support requires hwc.infrastructure.hardware.gpu.type = \"amd\" and GPU to be enabled";
      }
    ];
  };
}
