# domains/home/apps/blender/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.blender;

  hmLib = import ../../../lib/hm.nix { inherit lib; };
  isNixOSHost = hmLib.isNixOSHost osConfig;
  osCfg = hmLib.osCfgOr osConfig;
  gpuCfg = lib.attrByPath [ "hwc" "system" "hardware" "gpu" ] { type = "none"; enable = false; } osCfg;

  # Explicit package wins; otherwise fall back to nixpkgs' blender built for the
  # detected GPU. Mirrors the codex module's `package` option.
  blenderPackage =
    if cfg.package != null then cfg.package
    else pkgs.blender.override {
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

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Blender package to use. If null, uses `pkgs.blender` overridden per
        cudaSupport/rocmSupport — which on an nvidia host is a non-cached variant
        and rebuilds from source (~30 min) on every nixpkgs bump. Set this to
        `pkgs.callPackage ./parts/package.nix { }` for the official upstream
        binary instead (CUDA + OptiX kernels included, no compile).
      '';
    };

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
