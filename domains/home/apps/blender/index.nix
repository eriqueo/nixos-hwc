{ config, lib, pkgs, osConfig ? {}, ... }:

let
  enabled = config.hwc.home.apps.blender.enable or false;
  cfg = config.hwc.home.apps.blender;

  # Access system GPU config via osConfig (available in Home Manager)
  gpuCfg = osConfig.hwc.infrastructure.hardware.gpu or { type = "none"; enable = false; };

  # Use regular binary-cached Blender (no CUDA rebuild needed!)
  # GPU rendering works via NVIDIA offload environment variables
  blenderPackage = pkgs.blender;

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
      {
        assertion = !cfg.cudaSupport || (gpuCfg.enable && gpuCfg.type == "nvidia");
        message = "Blender CUDA support requires hwc.infrastructure.hardware.gpu.type = \"nvidia\" and GPU to be enabled";
      }
      {
        assertion = !cfg.hipSupport || (gpuCfg.enable && gpuCfg.type == "amd");
        message = "Blender HIP support requires hwc.infrastructure.hardware.gpu.type = \"amd\" and GPU to be enabled";
      }
    ];
  };
}
