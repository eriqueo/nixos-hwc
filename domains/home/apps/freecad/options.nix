{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.freecad = {
    enable = lib.mkEnableOption "Enable FreeCAD parametric 3D CAD modeler";

    gpuAcceleration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable GPU-accelerated OpenGL rendering.
        Provides freecad-gpu wrapper for explicit GPU offload on NVIDIA PRIME systems.
        Uses hardware.graphics configuration from infrastructure domain.
      '';
    };
  };
}