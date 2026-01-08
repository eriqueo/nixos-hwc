{ lib, ... }:

{
  options.hwc.home.apps.blender = {
    enable = lib.mkEnableOption "Enable Blender 3D creation suite";

    cudaSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable CUDA support for GPU rendering (NVIDIA)";
    };

    hipSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable HIP support for GPU rendering (AMD)";
    };
  };
}
