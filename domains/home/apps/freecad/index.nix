# domains/home/apps/freecad/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.freecad;

  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};
  gpuCfg = lib.attrByPath [ "hwc" "system" "hardware" "gpu" ] { type = "none"; enable = false; } osCfg;

  freecadPkg = pkgs.freecad.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./patches/arch-window-displaymode-guard.patch ];
  });

  freecadGpuWrapper = pkgs.writeShellScriptBin "freecad-gpu" ''
    #!/usr/bin/env bash
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export __GL_SHADER_DISK_CACHE=1
    export __GL_THREADED_OPTIMIZATIONS=1
    export QT_QPA_PLATFORM=xcb
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    exec ${freecadPkg}/bin/freecad "$@"
  '';

  freecadOptimizedWrapper = pkgs.writeShellScriptBin "freecad-optimized" ''
    #!/usr/bin/env bash
    export __GL_SHADER_DISK_CACHE=1
    export __GL_THREADED_OPTIMIZATIONS=1
    export QT_QPA_PLATFORM=xcb
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    exec ${freecadPkg}/bin/freecad "$@"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.freecad = {
    enable = lib.mkEnableOption "FreeCAD parametric 3D CAD modeler";

    gpuAcceleration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GPU-accelerated OpenGL rendering.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install FreeCAD package (binary-cached)
    home.packages = [
      freecadPkg
    ] ++ lib.optionals cfg.gpuAcceleration (
      if gpuCfg.type == "nvidia" && gpuCfg.enable then [
        # NVIDIA PRIME: provide explicit GPU offload wrapper
        freecadGpuWrapper
      ] else if gpuCfg.enable then [
        # Intel/AMD: provide optimized wrapper
        freecadOptimizedWrapper
      ] else []
    );

    # XDG desktop entry for FreeCAD (ensures proper application integration)
    xdg.desktopEntries.freecad = lib.mkIf cfg.gpuAcceleration {
      name = "FreeCAD (GPU)";
      genericName = "CAD Application";
      comment = "Parametric 3D modeler with GPU acceleration";
      exec = if gpuCfg.type == "nvidia" && gpuCfg.enable
             then "freecad-gpu %f"
             else "freecad-optimized %f";
      icon = "freecad";
      terminal = false;
      categories = [ "Graphics" "Science" "Engineering" ];
      mimeType = [ "application/x-extension-fcstd" ];
    };

    # Configure FreeCAD preferences for optimal GPU rendering
    # FreeCAD stores preferences in ~/.config/FreeCAD/user.cfg
    # NOTE: We use home.activation to COPY (not symlink) the initial config
    # so FreeCAD can write to it. Only applied if user.cfg doesn't exist.
    home.activation.freecadInitialConfig = lib.mkIf cfg.gpuAcceleration (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        FREECAD_CONFIG="$HOME/.config/FreeCAD/user.cfg"

        # Only create initial config if it doesn't exist (preserve user changes)
        if [ ! -f "$FREECAD_CONFIG" ]; then
          $DRY_RUN_CMD mkdir -p "$HOME/.config/FreeCAD"
          $DRY_RUN_CMD cat > "$FREECAD_CONFIG" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<FCParameters>
  <FCParamGroup Name="Root">
    <FCParamGroup Name="BaseApp">
      <FCParamGroup Name="Preferences">
        <FCParamGroup Name="View">
          <!-- Enable VBO (Vertex Buffer Objects) for better GPU performance -->
          <FCBool Name="UseVBO" Value="1"/>

          <!-- Enable modern OpenGL (Core Profile) -->
          <FCBool Name="UseOpenGLCoreProfile" Value="1"/>

          <!-- Disable software OpenGL fallback (use hardware acceleration) -->
          <FCBool Name="UseSoftwareOpenGL" Value="0"/>

          <!-- Anti-aliasing for smoother rendering (0=off, 1=line, 2=MSAA) -->
          <FCInt Name="AntiAliasing" Value="2"/>

          <!-- Enable hardware-accelerated selection -->
          <FCBool Name="UseSelectionRoot" Value="1"/>
        </FCParamGroup>
      </FCParamGroup>
    </FCParamGroup>
  </FCParamGroup>
</FCParameters>
EOF
          $DRY_RUN_CMD chmod 644 "$FREECAD_CONFIG"
        fi
      ''
    );

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      # GPU hardware validation (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where GPU config is available
      # On non-NixOS hosts, user is responsible for GPU driver setup
      {
        assertion = !cfg.gpuAcceleration || !isNixOSHost || gpuCfg.enable || gpuCfg.type == "none";
        message = ''
          FreeCAD GPU acceleration requires either:
          - hwc.system.hardware.gpu.enable = true (with type = "nvidia"/"intel"/"amd")
          - OR disable GPU acceleration: hwc.home.apps.freecad.gpuAcceleration = false
        '';
      }
    ];
  };
}
