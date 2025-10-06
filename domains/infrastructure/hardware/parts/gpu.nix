# HWC Charter Module/domains/system/gpu.nix
#
# GPU Hardware Acceleration Management
# Provides NVIDIA, Intel, AMD GPU support with hardware acceleration for services.
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.cache  (modules/system/paths.nix)
#   - config.hwc.paths.logs   (modules/system/paths.nix)
#   - config.time.timeZone    (system configuration)
#
# USED BY (Downstream):
#   - modules/services/media/jellyfin.nix  (GPU transcoding)
#   - modules/services/media/immich.nix    (ML acceleration)
#   - modules/services/ai/ollama.nix       (consumes accel = cuda/intel/rocm/cpu)
#   - profiles/*                           (orchestration)
#   - machines/*/config.nix                (declares hwc.infrastructure.hardware.gpu.type)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../domains/system/gpu.nix
#
# USAGE:
#   hwc.infrastructure.hardware.gpu.type = "nvidia";  # or "intel" | "amd" | "none"
#   hwc.infrastructure.hardware.gpu.nvidia.driver = "stable";  # "stable" | "beta" | "production"
#   hwc.infrastructure.hardware.gpu.nvidia.containerRuntime = true;   # enables nvidia-container-toolkit
#   hwc.infrastructure.hardware.gpu.nvidia.enableMonitoring = true;   # nvidia-smi logging service
#
# NOTES:
#   - This file assumes Podman is the OCI engine (recommended repo-wide):
#       virtualisation.podman.enable = true;
#       virtualisation.oci-containers.backend = "podman";
#     (If the backend differs, CDI hint is gated and safe.)

{ config, lib, pkgs, ... }:

let
  cfg   = config.hwc.infrastructure.hardware.gpu;
  paths = config.hwc.paths;
  t     = lib.types;

  # Derive a neutral acceleration signal for service consumers.
  accelFor = type:
    if type == "nvidia" then "cuda"
    else if type == "amd" then "rocm"
    else if type == "intel" then "intel"
    else "cpu";

  # Detect OCI engine for CDI hinting (defaults to podman if unset per repo standard)
  usingPodman = (config.virtualisation.oci-containers.backend or "podman") == "podman";

in
{
  #============================================================================
  # IMPLEMENTATION - GPU hardware acceleration
  #============================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [

    # --- Validation -----------------------------------------------------------
    {
      assertions = [
        {
          assertion = (!cfg.nvidia.containerRuntime) || (cfg.type != "none");
          message   = "GPU container runtime requires hwc.infrastructure.hardware.gpu.type to be nvidia/intel/amd (not 'none').";
        }
        {
          assertion = (!cfg.nvidia.enableMonitoring) || (cfg.type == "nvidia");
          message   = "NVIDIA monitoring requires hwc.infrastructure.hardware.gpu.type = \"nvidia\".";
        }
      ];
    }

    # --- Common graphics stack (all GPU types except 'none') ------------------
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };
    }

    # --- NVIDIA ---------------------------------------------------------------
    (lib.mkIf (cfg.type == "nvidia" && cfg.nvidia.enable) {
      # Desktop stack driver selection
      services.xserver.videoDrivers = [ "nvidia" ];

      # Core NVIDIA configuration (no nonexistent hardware.nvidia.enable)
      hardware.nvidia = {
        modesetting.enable = lib.mkDefault true;
        powerManagement.enable      = lib.mkDefault false;
        powerManagement.finegrained = lib.mkDefault false;
        open           = lib.mkDefault true;   # set false if you prefer proprietary
        nvidiaSettings = lib.mkDefault true;
        package        = config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver};
      };

      # PRIME offload for hybrid laptops
      hardware.nvidia.prime = lib.mkIf cfg.nvidia.prime.enable {
        offload.enable = true;
        nvidiaBusId    = cfg.nvidia.prime.nvidiaBusId;
        intelBusId     = cfg.nvidia.prime.intelBusId;
      };

      # Kernel modules and params
      boot = {
        kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
        blacklistedKernelModules = [ "nouveau" ];
        kernelParams = [ "nvidia-drm.modeset=1" ];
        extraModprobeConfig = ''
          # NVIDIA device file ownership/permissions
          options nvidia NVreg_DeviceFileUID=0 NVreg_DeviceFileGID=44 NVreg_DeviceFileMode=0660
          options nvidia NVreg_ModifyDeviceFiles=1

          # Persistence-leaning behavior
          options nvidia NVreg_RegistryDwords="PerfLevelSrc=0x2222"
        '';
      };

      # Runtime environment
      environment.sessionVariables = {
        CUDA_CACHE_PATH   = "${paths.cache}/cuda";
        LIBVA_DRIVER_NAME = "nvidia";
        VDPAU_DRIVER      = "nvidia";
      };

      # Useful tools
      environment.systemPackages = with pkgs; [
        config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}
        libva-utils
        vdpauinfo
      ];

      # NVIDIA container runtime (toolkit)
      hardware.nvidia-container-toolkit.enable = cfg.nvidia.containerRuntime;

      # CDI hint for Podman (harmless no-op on other engines)
      virtualisation.containers.containersConf.settings = lib.mkIf (usingPodman && cfg.nvidia.containerRuntime) {
        engine = { cdi_spec_dirs = [ "/var/run/cdi" ]; };
      };

      # Cache/logs dirs
      systemd.tmpfiles.rules = [
        "d ${paths.cache}/cuda 0755 root root -"
        "d ${paths.logs}/gpu  0755 root root -"
      ];

      # Optional: nvidia-smi monitoring
      systemd.services.gpu-monitor = lib.mkIf cfg.nvidia.enableMonitoring {
        description = "NVIDIA GPU utilization monitoring";
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = pkgs.writeShellScript "gpu-monitor" ''
            #!/usr/bin/env bash
            while true; do
              ${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}}/bin/nvidia-smi \
                --query-gpu=timestamp,name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total \
                --format=csv,noheader,nounits >> ${paths.logs}/gpu/gpu-usage.log
              sleep 60
            done
          '';
          Restart = "always";
          RestartSec = "10";
        };
        wantedBy = [ ];
      };
    })

    # --- Intel ----------------------------------------------------------------
    (lib.mkIf (cfg.type == "intel" && cfg.intel.enable) {
      services.xserver.videoDrivers = [ "modesetting" ];

      # Base graphics packages
      hardware.graphics.extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        libvdpau-va-gl
      ] ++ lib.optionals cfg.intel.enableCompute [
        # Intel GPU compute support for AI/ML workloads
        intel-compute-runtime  # OpenCL and Level Zero support
        level-zero             # oneAPI Level Zero for containerized workloads
      ];

      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "iHD"; # prefer modern Intel driver
      } // lib.optionalAttrs cfg.intel.enableCompute {
        # Level Zero configuration for compute
        NEOReadDebugKeys = "1";
        ZE_ENABLE_VALIDATION_LAYER = "0";  # Disable for production
      };

      environment.systemPackages = with pkgs; [
        libva-utils
        intel-gpu-tools
      ] ++ lib.optionals cfg.intel.enableMonitoring [
        # Monitoring tools
        igt-gpu-tools  # intel_gpu_top and more
      ] ++ lib.optionals cfg.intel.enableCompute [
        # Compute utilities
        clinfo  # Query OpenCL capabilities
      ];

      # Cache/logs dirs for Intel compute
      systemd.tmpfiles.rules = lib.optionals cfg.intel.enableCompute [
        "d ${paths.cache}/intel-compute 0755 root root -"
        "d ${paths.logs}/gpu  0755 root root -"
      ];

      # Optional: Intel GPU monitoring service
      systemd.services.intel-gpu-monitor = lib.mkIf cfg.intel.enableMonitoring {
        description = "Intel GPU utilization monitoring";
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = pkgs.writeShellScript "intel-gpu-monitor" ''
            #!/usr/bin/env bash
            while true; do
              ${pkgs.igt-gpu-tools}/bin/intel_gpu_top -J -s 5000 >> ${paths.logs}/gpu/intel-gpu-usage.log 2>&1 || true
              sleep 60
            done
          '';
          Restart = "always";
          RestartSec = "10";
        };
        wantedBy = [ ];  # Manual start only
      };
    })

    # --- AMD ------------------------------------------------------------------
    (lib.mkIf (cfg.type == "amd") {
      services.xserver.videoDrivers = [ "amdgpu" ];
      boot.kernelModules = [ "amdgpu" ];

      hardware.graphics.extraPackages = with pkgs; [
        libvdpau-va-gl
      ];
    })

    # --- Laptop helpers (optional) --------------------------------------------
    (lib.mkIf cfg.powerManagement.smartToggle {
      environment.systemPackages = with pkgs; [
        (pkgs.writeShellScriptBin "gpu-toggle" ''
          #!/usr/bin/env bash
          GPU_MODE_FILE="/run/waybar/gpu-mode"
          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

          case "$CURRENT_MODE" in
            "intel")
              echo "performance" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
              ''}
              ;;
            "performance")
              echo "intel" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
              ''}
              ;;
            *)
              echo "intel" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${pkgs.libnotify}/bin/notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
              ''}
              ;;
          esac
        '')

        (pkgs.writeShellScriptBin "gpu-next" ''
          #!/usr/bin/env bash
          touch /run/waybar/gpu-next-nvidia
          echo "Next application will use NVIDIA GPU"
          ${lib.optionalString cfg.powerManagement.toggleNotifications ''
            ${pkgs.libnotify}/bin/notify-send "GPU Override" "Next app will use NVIDIA dGPU" -i gpu-card
          ''}
        '')

        (pkgs.writeShellScriptBin "gpu-launch" ''
          #!/usr/bin/env bash
          if [[ $# -eq 0 ]]; then
            echo "Usage: gpu-launch <application> [args...]"
            exit 1
          fi

          GPU_MODE_FILE="/run/waybar/gpu-mode"
          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

          NEXT_NVIDIA_FILE="/run/waybar/gpu-next-nvidia"
          if [[ -f "$NEXT_NVIDIA_FILE" ]]; then
            rm "$NEXT_NVIDIA_FILE"
            exec ${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}}/bin/nvidia-offload "$@"
          fi

          case "$CURRENT_MODE" in
            "performance")
              case "$1" in
                blender|gimp|inkscape|kdenlive|obs|steam|wine|chromium|firefox|librewolf|godot|krita)
                  exec ${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}}/bin/nvidia-offload "$@"
                  ;;
                *)
                  exec "$@"
                  ;;
              esac
              ;;
            "intel"|*)
              exec "$@"
              ;;
          esac
        '')

        (pkgs.writeShellScriptBin "gpu-status" ''
          #!/usr/bin/env bash
          # Read from systemd-managed state to avoid FD leaks
          if [[ -f /run/waybar/gpu-status.json ]]; then
            cat /run/waybar/gpu-status.json
          else
            echo '{"text":"󰢮","class":"intel","tooltip":"GPU monitoring starting..."}'
          fi
        '')
      ];
    })
  ]);
}
