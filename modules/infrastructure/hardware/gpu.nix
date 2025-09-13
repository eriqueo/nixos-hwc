# nixos-hwc/modules/system/gpu.nix
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
#   - machines/*/config.nix                (declares hwc.gpu.type)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/gpu.nix
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
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.infrastructure.hardware.gpu = {
  
    enable = lib.mkEnableOption "GPU hardware acceleration support";

    type = lib.mkOption {
      type = t.enum [ "none" "nvidia" "intel" "amd" ];
      default = "none";
      description = "GPU type for hardware acceleration";
    };

    accel = lib.mkOption {
      type = t.enum [ "cuda" "rocm" "intel" "cpu" ];
      default = accelFor config.hwc.infrastructure.hardware.gpu.type;
      readOnly = true;
      description = "Derived acceleration target (cuda|rocm|intel|cpu) for services.";
    };

    powerManagement = {
      enable = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Enable GPU power management helpers.";
      };
      smartToggle = lib.mkOption {
        type = t.bool;
        default = false;
        description = "Install simple laptop GPU toggle helpers.";
      };
      toggleNotifications = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Show notifications when GPU mode changes.";
      };
    };

    nvidia = {
      enable = lib.mkOption {
        type = t.bool;
        default = cfg.type == "nvidia";
        description = "Enable NVIDIA support (auto-enabled when type = nvidia).";
      };

      driver = lib.mkOption {
        type = t.enum [ "stable" "beta" "production" ];
        default = "stable";
        description = "NVIDIA driver package channel.";
      };

      enableMonitoring = lib.mkEnableOption "Log GPU utilization with nvidia-smi (unit: gpu-monitor)";
      containerRuntime = lib.mkEnableOption "Enable NVIDIA container runtime (nvidia-container-toolkit)";

      prime = {
        enable = lib.mkOption {
          type = t.bool;
          default = true;
          description = "Enable PRIME offload (hybrid graphics).";
        };
        nvidiaBusId = lib.mkOption {
          type = t.str;
          default = "PCI:1:0:0";
          description = "NVIDIA GPU bus ID.";
        };
        intelBusId = lib.mkOption {
          type = t.str;
          default = "PCI:0:2:0";
          description = "Intel iGPU bus ID.";
        };
      };
    };

    intel = {
      enable = lib.mkOption {
        type = t.bool;
        default = cfg.type == "intel";
        description = "Enable Intel GPU support (auto-enabled when type = intel).";
      };
    };

    # Exported flags for services to passthrough devices to containers.
    containerOptions = lib.mkOption {
      type = t.listOf t.str;
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
        ] else if cfg.type == "amd" then [
          "--device=/dev/dri:/dev/dri"
        ] else [];
      description = "Container CLI device flags for GPU access (auto-generated).";
    };

    containerEnvironment = lib.mkOption {
      type = t.attrsOf t.str;
      default =
        if cfg.type == "nvidia" then {
          NVIDIA_VISIBLE_DEVICES = "all";
          NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
        } else {};
      description = "Container env vars for GPU access (auto-generated).";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [

    # --- Validation -----------------------------------------------------------
    {
      assertions = [
        {
          assertion = (!cfg.nvidia.containerRuntime) || (cfg.type != "none");
          message   = "GPU container runtime requires hwc.gpu.type to be nvidia/intel/amd (not 'none').";
        }
        {
          assertion = (!cfg.nvidia.enableMonitoring) || (cfg.type == "nvidia");
          message   = "NVIDIA monitoring requires hwc.gpu.type = \"nvidia\".";
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
          GPU_MODE_FILE="/tmp/gpu-mode"
          DEFAULT_MODE="intel"

          if [[ ! -f "$GPU_MODE_FILE" ]]; then
            echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
          fi

          CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")
          CURRENT_GPU=$(${pkgs.mesa-demos}/bin/glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs || echo "Unknown")
          ${lib.optionalString (cfg.type == "nvidia") ''
            NVIDIA_POWER=$(${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}}/bin/nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
            NVIDIA_TEMP=$(${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}}/bin/nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
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
