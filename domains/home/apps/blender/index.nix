{ config, lib, pkgs, osConfig ? {}, ... }:

let
  enabled = config.hwc.home.apps.blender.enable or false;
  cfg = config.hwc.home.apps.blender;

  # Access system GPU config via osConfig (available in Home Manager)
  gpuCfg = osConfig.hwc.infrastructure.hardware.gpu or { type = "none"; enable = false; };

  # Build Blender with appropriate GPU support
  blenderPackage = pkgs.blender.override {
    cudaSupport = cfg.cudaSupport && (gpuCfg.type == "nvidia");
    hipSupport = cfg.hipSupport && (gpuCfg.type == "amd");
  };
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
    home.packages = [ blenderPackage ];

    # Set environment variables for CUDA if enabled
    home.sessionVariables = lib.mkIf (cfg.cudaSupport && gpuCfg.type == "nvidia") {
      # Blender respects these for CUDA rendering
      CYCLES_CUDA_EXTRA_CFLAGS = "-I${pkgs.cudaPackages.cudatoolkit}/include";
    };

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
