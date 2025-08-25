# nixos-hwc/modules/system/gpu.nix
#
# GPU Hardware Acceleration Management
# Provides NVIDIA and Intel GPU support with hardware acceleration for media services
#
# DEPENDENCIES:
#   Upstream: config.hwc.paths.cache (modules/system/paths.nix)
#   Upstream: config.hwc.paths.logs (modules/system/paths.nix)
#   Upstream: config.time.timeZone (system configuration)
#
# USED BY:
#   Downstream: modules/services/media/jellyfin.nix (GPU transcoding)
#   Downstream: modules/services/media/immich.nix (ML acceleration)
#   Downstream: profiles/media.nix (enables GPU for media services)
#   Downstream: machines/server/config.nix (specifies GPU type)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/gpu.nix
#   - Any machine using GPU acceleration
#
# USAGE:
#   hwc.gpu.type = "nvidia";  # or "intel" or "none"
#   hwc.gpu.nvidia.driver = "stable";
#   hwc.gpu.nvidia.enableMonitoring = true;
#   hwc.gpu.nvidia.containerRuntime = true;
#
# VALIDATION:
#   - GPU type must be valid enum value
#   - NVIDIA options only apply when type = "nvidia"
#   - Container runtime requires GPU type to be set

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.gpu;
  paths = config.hwc.paths;
in {


  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================

  options.hwc.gpu = {
    type = lib.mkOption {
      type = lib.types.enum [ "none" "nvidia" "intel" "amd" ];
      default = "none";
      description = "GPU type for hardware acceleration";
    };

    # GPU power management and toggle functionality
    powerManagement = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable GPU power management features";
      };

      smartToggle = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable smart GPU toggle functionality for laptops";
      };

      toggleNotifications = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show desktop notifications when GPU mode changes";
      };
    };

    nvidia = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.type == "nvidia";
        description = "Enable NVIDIA GPU support (auto-enabled when type=nvidia)";
      };

      driver = lib.mkOption {
        type = lib.types.enum [ "stable" "beta" "production" ];
        default = "stable";
        description = "NVIDIA driver version";
      };

      enableMonitoring = lib.mkEnableOption "GPU utilization monitoring";

      containerRuntime = lib.mkEnableOption "NVIDIA container runtime for Docker/Podman";

      prime = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable NVIDIA Prime for hybrid graphics";
        };

        nvidiaBusId = lib.mkOption {
          type = lib.types.str;
          default = "PCI:1:0:0";
          description = "NVIDIA GPU bus ID";
        };

        intelBusId = lib.mkOption {
          type = lib.types.str;
          default = "PCI:0:2:0";
          description = "Intel GPU bus ID";
        };
      };
    };

    intel = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.type == "intel";
        description = "Enable Intel GPU support (auto-enabled when type=intel)";
      };
    };

    # Export GPU options for container services
    containerOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if cfg.type == "nvidia" then [
          "--device=/dev/nvidia0:/dev/nvidia0:rwm"
          "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
          "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
          "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
          "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
          "--device=/dev/dri:/dev/dri:rwm"
        ] else if cfg.type == "intel" then [
          "--device=/dev/dri:/dev/dri"
        ] else [];
      description = "Container options for GPU access (auto-generated based on GPU type)";
    };

    containerEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default =
        if cfg.type == "nvidia" then {
          NVIDIA_VISIBLE_DEVICES = "all";
          NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
        } else {};
      description = "Container environment variables for GPU access (auto-generated based on GPU type)";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================

  config = lib.mkMerge [


    # Validation assertions
    {
      assertions = [
        {
          assertion = cfg.nvidia.containerRuntime -> (cfg.type != "none");
          message = "GPU container runtime requires hwc.gpu.type to be set to nvidia, intel, or amd";
        }
        {
          assertion = cfg.nvidia.enableMonitoring -> (cfg.type == "nvidia");
          message = "NVIDIA monitoring requires hwc.gpu.type = \"nvidia\"";
        }
      ];
    }

    # NVIDIA GPU Configuration
    (lib.mkIf cfg.nvidia.enable {
      # Enable Graphics (updated from hardware.opengl)
      hardware.graphics = {
        enable = true;
        enable32Bit = true;

        # Add drivers for both Intel iGPU and NVIDIA
        extraPackages = with pkgs; [
          # Intel iGPU acceleration (fallback for basic tasks)
          intel-media-driver      # LIBVA_DRIVER_NAME=iHD
          intel-vaapi-driver      # LIBVA_DRIVER_NAME=i965 (fallback)
          libvdpau-va-gl

          # NVIDIA acceleration packages
          nvidia-vaapi-driver     # For VAAPI support
          vaapiVdpau             # VDPAU to VAAPI bridge
        ];
      };

      # Load nvidia driver for Xorg and Wayland
      services.xserver.videoDrivers = [ "nvidia" ];

      # NVIDIA GPU Configuration
      hardware.nvidia = {
        # Modesetting is required for proper operation
        modesetting.enable = true;

        # Power management settings for server (24/7 operation)
        powerManagement.enable = false;        # Disable for server stability
        powerManagement.finegrained = false;  # Not needed for server workloads

        # Use open-source drivers (updated from false to true)
        open = true;

        # Enable NVIDIA settings
        nvidiaSettings = true;

        # Use specified driver version
        package = config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver};
      };

      # Prime configuration (updated from sync to offload)
      hardware.nvidia.prime = lib.mkIf cfg.nvidia.prime.enable {
        offload.enable = true;  # Changed from sync.enable = true
        nvidiaBusId = cfg.nvidia.prime.nvidiaBusId;
        intelBusId = cfg.nvidia.prime.intelBusId;
      };

      # Load NVIDIA kernel modules early in boot process
      boot.kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
      boot.blacklistedKernelModules = [ "nouveau" ];  # Disable nouveau

      # Kernel parameters for NVIDIA
      boot.kernelParams = [
        "nvidia-drm.modeset=1"  # Enable DRM kernel mode setting
      ];

      # Environment variables for GPU acceleration
      environment.sessionVariables = {
        # NVIDIA specific
        CUDA_CACHE_PATH = "${paths.cache}/cuda";

        # VAAPI driver selection (prefer NVIDIA, fallback to Intel)
        LIBVA_DRIVER_NAME = "nvidia";

        # VDPAU driver
        VDPAU_DRIVER = "nvidia";
      };

      # Install GPU utilities and monitoring tools
      environment.systemPackages = with pkgs; [
        # NVIDIA tools - use the driver package which includes nvidia-smi
        config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}

        # Video acceleration testing tools
        libva-utils             # vainfo command
        vdpauinfo               # VDPAU info
      ];

      # Enable container GPU support
      hardware.nvidia-container-toolkit.enable = cfg.nvidia.containerRuntime;

      # Configure CDI support for containers
      virtualisation.containers.containersConf.settings = lib.mkIf cfg.nvidia.containerRuntime {
        engine = {
          cdi_spec_dirs = ["/var/run/cdi"];
        };
      };

      # Create GPU cache and monitoring directories
      systemd.tmpfiles.rules = [
        "d ${paths.cache}/cuda 0755 root root -"
        "d ${paths.logs}/gpu 0755 root root -"
      ];

      # GPU monitoring service
      systemd.services.gpu-monitor = lib.mkIf cfg.nvidia.enableMonitoring {
        description = "GPU utilization monitoring";
        serviceConfig = {
          Type = "simple";
          User = "root";
          ExecStart = pkgs.writeShellScript "gpu-monitor" ''
            #!/bin/bash
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
        # Don't auto-start - enable manually when needed for monitoring
        wantedBy = [ ];
      };

      # Kernel module options for optimal server performance
      boot.extraModprobeConfig = ''
        # NVIDIA optimizations for server workloads
        options nvidia NVreg_DeviceFileUID=0 NVreg_DeviceFileGID=44 NVreg_DeviceFileMode=0660
        options nvidia NVreg_ModifyDeviceFiles=1

        # Persistence mode for consistent performance
        options nvidia NVreg_RegistryDwords="PerfLevelSrc=0x2222"
      '';
    })

    # Intel GPU Configuration
    (lib.mkIf cfg.intel.enable {
      # Enable Graphics for Intel
      hardware.graphics = {
        enable = true;
        enable32Bit = true;

        extraPackages = with pkgs; [
          intel-media-driver      # LIBVA_DRIVER_NAME=iHD
          intel-vaapi-driver      # LIBVA_DRIVER_NAME=i965
          libvdpau-va-gl
        ];
      };

      # Environment variables for Intel GPU
      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "iHD";  # Use Intel iHD driver
      };

      # Install Intel GPU utilities
      environment.systemPackages = with pkgs; [
        libva-utils             # vainfo command
        intel-gpu-tools         # intel_gpu_top
      ];
    })

    # GPU toggle scripts (migrated from waybar.nix for proper domain organization)
    (lib.mkIf cfg.powerManagement.smartToggle {
      environment.systemPackages = with pkgs; [
        (writeScriptBin "gpu-toggle" ''
          #!/usr/bin/env bash
          GPU_MODE_FILE="/tmp/gpu-mode"
          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

          case "$CURRENT_MODE" in
            "intel")
              echo "performance" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${libnotify}/bin/notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
              ''}
              ;;
            "performance")
              echo "intel" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${libnotify}/bin/notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
              ''}
              ;;
            *)
              echo "intel" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${libnotify}/bin/notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
              ''}
              ;;
          esac

          # Update UI components if available (generic notification)
          pkill -SIGUSR1 waybar 2>/dev/null || true  # Legacy waybar support
          pkill -SIGUSR1 swaybar 2>/dev/null || true  # Future sway support
        '')

        (writeScriptBin "gpu-launch" ''
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

        # Manual dGPU override command
        (writeScriptBin "gpu-next" ''
          #!/usr/bin/env bash
          touch /tmp/gpu-next-nvidia
          echo "Next application will use NVIDIA GPU"
          ${lib.optionalString cfg.powerManagement.toggleNotifications ''
            ${libnotify}/bin/notify-send "GPU Override" "Next app will use NVIDIA dGPU" -i gpu-card
          ''}
        '')

        # GPU status script for waybar/status bars
        (writeScriptBin "gpu-status" ''
          #!/usr/bin/env bash
          GPU_MODE_FILE="/tmp/gpu-mode"
          DEFAULT_MODE="intel"

          if [[ ! -f "$GPU_MODE_FILE" ]]; then
            echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
          fi

          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")
          CURRENT_GPU=$(${pkgs.mesa-demos}/bin/glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
          ${lib.optionalString (cfg.type == "nvidia") ''
            NVIDIA_POWER=$(${pkgs.linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
            NVIDIA_TEMP=$(${pkgs.linuxPackages.nvidia_x11}/bin/nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
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
                TOOLTIP="NVIDIA Mode: $CURRENT_GPU\\nPower: $NVIDIA_POWER W | Temp: $NVIDIA_TEMP°C"
              ''}
              ;;
            "performance")
              ICON="⚡"
              CLASS="performance"
              ${lib.optionalString (cfg.type == "nvidia") ''
                TOOLTIP="Performance Mode: Auto-GPU Selection\\nNVIDIA: $NVIDIA_POWER W | $NVIDIA_TEMP°C"
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

        # GPU toggle script for interactive switching
        (writeScriptBin "gpu-toggle" ''
          #!/usr/bin/env bash
          GPU_MODE_FILE="/tmp/gpu-mode"
          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "intel")

          case "$CURRENT_MODE" in
            "intel")
              echo "performance" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${libnotify}/bin/notify-send "GPU Mode" "Switched to Performance Mode ⚡" -i gpu-card
              ''}
              ;;
            "performance")
              echo "intel" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${libnotify}/bin/notify-send "GPU Mode" "Switched to Intel Mode 󰢮" -i gpu-card
              ''}
              ;;
            *)
              echo "intel" > "$GPU_MODE_FILE"
              ${lib.optionalString cfg.powerManagement.toggleNotifications ''
                ${libnotify}/bin/notify-send "GPU Mode" "Reset to Intel Mode 󰢮" -i gpu-card
              ''}
              ;;
          esac

          # Signal waybar to update
          ${pkgs.procps}/bin/pkill -SIGUSR1 waybar 2>/dev/null || true
        '')
      ];
    })
  ];
}

