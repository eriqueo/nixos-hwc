{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.blender = {
    enable = lib.mkEnableOption "Enable Blender 3D creation suite";

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable CUDA GPU rendering support (NVIDIA).
        Provides blender-gpu wrapper and configures GPU offload.
        Uses binary-cached Blender (no rebuild required).
      '';
    };

    hipSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable HIP support for GPU rendering (AMD)";
    };
  };
}