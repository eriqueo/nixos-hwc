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

      # Udev rules to ensure nvidia devices are accessible by all users
      services.udev.extraRules = ''
        KERNEL=="nvidia[0-9]*", MODE="0666"
        KERNEL=="nvidia-modeset", MODE="0666"
        KERNEL=="nvidia-uvm", MODE="0666"
        KERNEL=="nvidia-uvm-tools", MODE="0666"
        KERNEL=="nvidiactl", MODE="0666"
      '';

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
        wantedBy = [ "multi-user.target" ];
      };
    })

    # --- Intel ----------------------------------------------------------------
    (lib.mkIf (cfg.type == "intel" && cfg.intel.enable) {
      services.xserver.videoDrivers = [ "modesetting" ];

      # Keep enable flags common; only add extra packages here
      hardware.graphics.extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        libvdpau-va-gl
      ];

      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "iHD"; # prefer modern Intel driver
      };

      environment.systemPackages = with pkgs; [
        libva-utils
        intel-gpu-tools
      ];
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
          GPU_MODE_FILE="/tmp/gpu-mode"
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

          ${pkgs.procps}/bin/pkill -SIGUSR1 waybar 2>/dev/null || true
          ${pkgs.procps}/bin/pkill -SIGUSR1 swaybar 2>/dev/null || true
        '')

        (pkgs.writeShellScriptBin "gpu-next" ''
          #!/usr/bin/env bash
          touch /tmp/gpu-next-nvidia
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

          GPU_MODE_FILE="/tmp/gpu-mode"
          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

          NEXT_NVIDIA_FILE="/tmp/gpu-next-nvidia"
          if [[ -f "$NEXT_NVIDIA_FILE" ]]; then
            rm "$NEXT_NVIDIA_FILE"
            # Use nvidia-offload environment variables
            if command -v nvidia-smi >/dev/null 2>&1; then
              export __NV_PRIME_RENDER_OFFLOAD=1
              export __GLX_VENDOR_LIBRARY_NAME=nvidia
              export __VK_LAYER_NV_optimus=NVIDIA_only
            fi
            exec "$@"
          fi

          case "$CURRENT_MODE" in
            "performance")
              case "$1" in
                blender|gimp|inkscape|kdenlive|obs|steam|wine|chromium|firefox|librewolf|godot|krita)
                  # Use nvidia-offload environment variables
                  if command -v nvidia-smi >/dev/null 2>&1; then
                    export __NV_PRIME_RENDER_OFFLOAD=1
                    export __GLX_VENDOR_LIBRARY_NAME=nvidia
                    export __VK_LAYER_NV_optimus=NVIDIA_only
                  fi
                  exec "$@"
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
          GPU_MODE_FILE="/tmp/gpu-mode"
          DEFAULT_MODE="intel"

          if [[ ! -f "$GPU_MODE_FILE" ]]; then
            echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
          fi

          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")
          CURRENT_GPU=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
          ${lib.optionalString (cfg.type == "nvidia") ''
            NVIDIA_POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
            NVIDIA_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
          ''}

          case "$CURRENT_MODE" in
            "intel")
              ICON="󰢮"
              CLASS="intel"
              TOOLTIP="Intel Mode: $CURRENT_GPU"
              ;;
            "nvidia")
              ICON="󰾲"
              CLASS="nvidia"
              ${lib.optionalString (cfg.type == "nvidia") ''
                TOOLTIP="NVIDIA Mode: $CURRENT_GPU\nPower: $NVIDIA_POWER W | Temp: $NVIDIA_TEMP°C"
              ''}
              ;;
            "performance")
              ICON="⚡"
              CLASS="performance"
              ${lib.optionalString (cfg.type == "nvidia") ''
                TOOLTIP="Performance Mode: Auto-GPU Selection\nNVIDIA: $NVIDIA_POWER W | $NVIDIA_TEMP°C"
              ''}
              ;;
            *)
              ICON="󰢮"
              CLASS="intel"
              TOOLTIP="Intel Mode (Default): $CURRENT_GPU"
              ;;
          esac

          echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
        '')
      ];
    })
  ]);
}
