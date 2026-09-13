# domains/system/gpu/index.nix
#
# GPU Hardware Acceleration Management
# Provides NVIDIA, Intel, AMD GPU support with hardware acceleration for services.
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.cache  (domains/paths/paths.nix)
#   - config.hwc.paths.logs   (domains/paths/paths.nix)
#   - config.time.timeZone    (system configuration)
#
# USED BY (Downstream):
#   - domains/server/native/jellyfin/  (GPU transcoding)
#   - domains/server/native/immich/    (ML acceleration)
#   - domains/ai/ollama/               (consumes accel = cuda/intel/rocm/cpu)
#   - profiles/*                       (orchestration)
#   - machines/*/config.nix            (declares hwc.system.hardware.gpu.type)
#
# USAGE:
#   hwc.system.hardware.gpu.type = "nvidia";  # or "intel" | "amd" | "none"
#   hwc.system.hardware.gpu.nvidia.driver = "stable";  # "stable" | "beta" | "production"
#   hwc.system.hardware.gpu.nvidia.containerRuntime = true;   # enables nvidia-container-toolkit
#   hwc.system.hardware.gpu.nvidia.enableMonitoring = true;   # nvidia-smi logging service
#
# NOTES:
#   - This file assumes Podman is the OCI engine (recommended repo-wide):
#       virtualisation.podman.enable = true;
#       virtualisation.oci-containers.backend = "podman";
#     (If the backend differs, CDI hint is gated and safe.)

{
  config,
  lib,
  pkgs,
  nixosApiVersion ? "unstable",
  ...
}:

let
  cfg = config.hwc.system.hardware.gpu;
  paths = config.hwc.paths;
  t = lib.types;

  # Cross-version API compatibility flag
  # 24.05 uses hardware.opengl, 24.11+ uses hardware.graphics
  # nixosApiVersion is passed from flake.nix ("stable" for server, "unstable" for laptop)
  # 24.11 stable now uses hardware.graphics API
  useStableApi = false; # 24.11+ uses hardware.graphics

  # Derive a neutral acceleration signal for service consumers.
  accelFor =
    type:
    if type == "nvidia" then
      "cuda"
    else if type == "amd" then
      "rocm"
    else if type == "intel" then
      "intel"
    else
      "cpu";

  # Detect OCI engine for CDI hinting (defaults to podman if unset per repo standard)
  usingPodman = (config.virtualisation.oci-containers.backend or "podman") == "podman";

  # One producer for intentional NVIDIA PRIME offload. Hybrid sessions pin EGL
  # to Mesa below, so an opt-in launch must remove that pin before restoring the
  # complete NVIDIA selection vocabulary.
  nvidiaOffload = pkgs.writeShellScriptBin "gpu-offload" ''
    #!/usr/bin/env bash
    if [[ $# -eq 0 ]]; then
      echo "Usage: gpu-offload <application> [args...]" >&2
      exit 64
    fi

    unset __EGL_VENDOR_LIBRARY_FILENAMES
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec "$@"
  '';

  # Ordinary hybrid clients should not be able to wake NVIDIA merely by
  # enumerating render devices. Keep the policy here, opposite gpu-offload,
  # and discover DRM ownership dynamically because card numbers are not stable.
  gpuIntegrated = pkgs.writeShellScriptBin "gpu-integrated" ''
    #!/usr/bin/env bash
    if [[ $# -eq 0 ]]; then
      echo "Usage: gpu-integrated <application> [args...]" >&2
      exit 64
    fi

    shopt -s nullglob
    nvidia_devices=()

    for device in /dev/nvidia* /dev/nvidia-caps/*; do
      [[ -e "$device" && ! -d "$device" ]] || continue
      nvidia_devices+=("$device")
    done

    for device in /dev/dri/card* /dev/dri/renderD*; do
      [[ -e "$device" ]] || continue
      vendor=$(cat "/sys/class/drm/$(basename "$device")/device/vendor" 2>/dev/null || true)
      [[ "$vendor" == "0x10de" ]] || continue
      nvidia_devices+=("$device")
    done

    if (( ''${#nvidia_devices[@]} == 0 )); then
      exec "$@"
    fi

    bwrap_args=(--bind / / --dev-bind /dev /dev --die-with-parent)
    for device in "''${nvidia_devices[@]}"; do
      bwrap_args+=(--ro-bind /dev/null "$device")
    done

    exec ${pkgs.bubblewrap}/bin/bwrap "''${bwrap_args[@]}" "$@"
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.system.hardware.gpu = {

    enable = lib.mkEnableOption "GPU hardware acceleration support";

    type = lib.mkOption {
      type = t.enum [
        "none"
        "nvidia"
        "intel"
        "amd"
      ];
      default = "none";
      description = "GPU type for hardware acceleration";
    };

    accel = lib.mkOption {
      type = t.enum [
        "cuda"
        "rocm"
        "intel"
        "cpu"
      ];
      default = accelFor cfg.type;
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
        type = t.enum [
          "stable"
          "beta"
          "production"
        ];
        default = "stable";
        description = "NVIDIA driver package channel.";
      };

      enableMonitoring = lib.mkEnableOption "Log GPU utilization with nvidia-smi (unit: gpu-monitor)";
      containerRuntime = lib.mkEnableOption "Enable NVIDIA container runtime (nvidia-container-toolkit)";

      prime = {
        enable = lib.mkOption {
          type = t.bool;
          default = false;
          description = ''
            Enable PRIME offload (hybrid graphics — Intel iGPU primary, NVIDIA
            dGPU on-demand). Set true ONLY on hybrid laptops. On NVIDIA-only
            hosts (server) leave it false — otherwise PRIME offload config is
            written for non-existent Intel bus IDs, and LIBVA_DRIVER_NAME is
            forced to iHD (wrong on a system with no Intel iGPU).
          '';
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

    containerOptions = lib.mkOption {
      type = t.listOf t.str;
      default =
        if cfg.type == "nvidia" then
          [
            "--device=/dev/nvidia0:/dev/nvidia0:rwm"
            "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
            "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
            "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
            "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
            "--device=/dev/dri:/dev/dri:rwm"
          ]
        else if cfg.type == "intel" then
          [
            "--device=/dev/dri:/dev/dri"
          ]
        else if cfg.type == "amd" then
          [
            "--device=/dev/dri:/dev/dri"
          ]
        else
          [ ];
      description = "Container CLI device flags for GPU access (auto-generated).";
    };

    containerEnvironment = lib.mkOption {
      type = t.attrsOf t.str;
      default =
        if cfg.type == "nvidia" then
          {
            NVIDIA_VISIBLE_DEVICES = "all";
            NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
          }
        else
          { };
      description = "Container env vars for GPU access (auto-generated).";
    };
  };

  #============================================================================
  # IMPLEMENTATION - GPU hardware acceleration
  #============================================================================
  config = lib.mkIf cfg.enable (
    lib.mkMerge [

      # --- Validation -----------------------------------------------------------
      {
        assertions = [
          {
            assertion = (!cfg.nvidia.containerRuntime) || (cfg.type != "none");
            message = "GPU container runtime requires hwc.system.hardware.gpu.type to be nvidia/intel/amd (not 'none').";
          }
          {
            assertion = (!cfg.nvidia.enableMonitoring) || (cfg.type == "nvidia");
            message = "NVIDIA monitoring requires hwc.system.hardware.gpu.type = \"nvidia\".";
          }
        ];
      }

      # --- Common graphics stack (all GPU types except 'none') ------------------
      # Cross-version compatibility: 24.05 uses hardware.opengl, 24.11+ uses hardware.graphics
      (
        if useStableApi then
          {
            # NixOS 24.05 API
            hardware.opengl = {
              enable = true;
              driSupport = true;
              driSupport32Bit = true;
            };
          }
        else
          {
            # NixOS 24.11+ / unstable API
            hardware.graphics = {
              enable = true;
              enable32Bit = true;
              extraPackages = [
                pkgs.cudaPackages.cudatoolkit
              ];
            };
          }
      )

      # --- NVIDIA ---------------------------------------------------------------
      (lib.mkIf (cfg.type == "nvidia" && cfg.nvidia.enable) {
        # Official NixOS CUDA binary cache (moved from cachix Nov 2025)
        # https://wiki.nixos.org/wiki/CUDA — every nvidia machine wants this,
        # so it lives here instead of being duplicated per machine file.
        nix.settings = {
          substituters = [ "https://cache.nixos-cuda.org" ];
          trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
        };

        # Desktop stack driver selection
        services.xserver.videoDrivers = [ "nvidia" ];

        # Core NVIDIA configuration (no nonexistent hardware.nvidia.enable)
        hardware.nvidia = {
          modesetting.enable = lib.mkDefault true;
          powerManagement.enable = lib.mkDefault false;
          powerManagement.finegrained = lib.mkDefault false;
          open = lib.mkDefault false; # proprietary driver for CUDA/OptiX
          nvidiaSettings = lib.mkDefault true;
          package = config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver};
        };

        # PRIME offload for hybrid laptops
        hardware.nvidia.prime = lib.mkIf cfg.nvidia.prime.enable {
          offload.enable = true;
          nvidiaBusId = cfg.nvidia.prime.nvidiaBusId;
          intelBusId = cfg.nvidia.prime.intelBusId;
        };

        # Kernel modules and params
        boot = {
          kernelModules = [
            "nvidia"
            "nvidia_modeset"
            "nvidia_uvm"
            "nvidia_drm"
          ];
          blacklistedKernelModules = [ "nouveau" ];
          kernelParams = [ "nvidia-drm.modeset=1" ];
          extraModprobeConfig = ''
            # NVIDIA device file ownership/permissions
            # Use video group (26) for device file access
            options nvidia NVreg_DeviceFileUID=0 NVreg_DeviceFileGID=26 NVreg_DeviceFileMode=0660
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
        #
        # PRIME-offload hybrids (laptop): Intel iGPU is the primary renderer for
        # the compositor, browsers, everything graphical. NVIDIA is reserved for
        # explicit per-process opt-in via `gpu-launch` / `blender-offload`.
        # Setting LIBVA_DRIVER_NAME=nvidia globally on a hybrid forces every
        # VA-API client (mpv, ffmpeg, browser HW decode) onto the dGPU which
        # the apps then can't reach because their EGL context is Intel — and
        # poisons the compositor with NVIDIA libs loaded into its process,
        # which is what was crashing Hyprland on WebGL use.
        #
        # Pure-NVIDIA hosts (server, prime.enable=false): nvidia is correct.
        environment.sessionVariables = {
          CUDA_CACHE_PATH = "${paths.cache}/cuda";
        }
        // (
          if cfg.nvidia.prime.enable then
            {
              LIBVA_DRIVER_NAME = "iHD"; # Intel iGPU does VA-API on hybrids
              # libglvnd otherwise enumerates both vendors for ordinary Wayland EGL
              # clients. That loads NVIDIA libraries and opens the dGPU even though
              # Intel owns the display. Explicit offload goes through gpu-offload,
              # which removes this pin before selecting NVIDIA.
              __EGL_VENDOR_LIBRARY_FILENAMES = "${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
              # VDPAU intentionally unset — VDPAU is X11/NVIDIA-era; Wayland
              # clients use VA-API. Leaving it unset prevents libvdpau-nvidia
              # from being loaded into Intel-context processes.
            }
          else
            {
              LIBVA_DRIVER_NAME = "nvidia";
              VDPAU_DRIVER = "nvidia";
            }
        );

        # Useful tools
        environment.systemPackages =
          with pkgs;
          [
            config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}
            libva-utils
            vdpauinfo
          ]
          ++ lib.optionals cfg.nvidia.prime.enable [
            gpuIntegrated
            nvidiaOffload
          ];

        # NVIDIA container runtime (toolkit)
        hardware.nvidia-container-toolkit.enable = cfg.nvidia.containerRuntime;

        # CDI hint for Podman (harmless no-op on other engines)
        virtualisation.containers.containersConf.settings =
          lib.mkIf (usingPodman && cfg.nvidia.containerRuntime)
            {
              engine = {
                cdi_spec_dirs = [ "/var/run/cdi" ];
              };
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
                ${config.boot.kernelPackages.nvidiaPackages.${cfg.nvidia.driver}.bin}/bin/nvidia-smi \
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
      (lib.mkIf (cfg.type == "intel" && cfg.intel.enable) (
        lib.mkMerge [
          {
            services.xserver.videoDrivers = [ "modesetting" ];

            environment.sessionVariables = {
              LIBVA_DRIVER_NAME = "iHD"; # prefer modern Intel driver
            };

            environment.systemPackages = with pkgs; [
              libva-utils
              intel-gpu-tools
            ];
          }

          # Cross-version compatibility for extra packages
          (
            if useStableApi then
              {
                hardware.opengl.extraPackages = with pkgs; [
                  intel-media-driver
                  intel-vaapi-driver
                  libvdpau-va-gl
                ];
              }
            else
              {
                hardware.graphics.extraPackages = with pkgs; [
                  intel-media-driver
                  intel-vaapi-driver
                  libvdpau-va-gl
                ];
              }
          )
        ]
      ))

      # --- AMD ------------------------------------------------------------------
      (lib.mkIf (cfg.type == "amd") (
        lib.mkMerge [
          {
            services.xserver.videoDrivers = [ "amdgpu" ];
            boot.kernelModules = [ "amdgpu" ];
          }

          # Cross-version compatibility for extra packages
          (
            if useStableApi then
              {
                hardware.opengl.extraPackages = with pkgs; [
                  libvdpau-va-gl
                ];
              }
            else
              {
                hardware.graphics.extraPackages = with pkgs; [
                  libvdpau-va-gl
                ];
              }
          )
        ]
      ))

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

            # Note: Waybar auto-updates via interval (5s), no signal needed
            # Previous pkill -SIGUSR1 caused waybar crashes - removed
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
              exec ${nvidiaOffload}/bin/gpu-offload "$@"
            fi

            case "$CURRENT_MODE" in
              "performance")
                case "$1" in
                  blender|gimp|inkscape|kdenlive|obs|steam|wine|chromium|firefox|godot|krita)
                    exec ${nvidiaOffload}/bin/gpu-offload "$@"
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

          (pkgs.writeShellScriptBin "blender-offload" ''
            #!/usr/bin/env bash
            if ! command -v blender >/dev/null 2>&1; then
              echo "blender not found on PATH"
              exit 1
            fi
            exec ${nvidiaOffload}/bin/gpu-offload blender "$@"
          '')

          (pkgs.writeShellScriptBin "gpu-status" ''
            #!/usr/bin/env bash
            GPU_MODE_FILE="/tmp/gpu-mode"
            DEFAULT_MODE="intel"

            if [[ ! -f "$GPU_MODE_FILE" ]]; then
              echo "$DEFAULT_MODE" > "$GPU_MODE_FILE"
            fi

            CURRENT_MODE=$(cat "$GPU_MODE_FILE" 2>/dev/null || echo "$DEFAULT_MODE")

            # Hardcoded GPU names (glxinfo removed to prevent CPU temperature spikes)
            INTEL_GPU="Intel Graphics"
            NVIDIA_GPU="NVIDIA RTX 2000 Ada"

            NVIDIA_STATE="unavailable"
            ${lib.optionalString (cfg.type == "nvidia") ''
              for device in /sys/bus/pci/devices/*; do
                [[ "$(cat "$device/vendor" 2>/dev/null || true)" == "0x10de" ]] || continue
                [[ "$(cat "$device/class" 2>/dev/null || true)" == 0x03* ]] || continue
                NVIDIA_STATE=$(cat "$device/power/runtime_status" 2>/dev/null || echo "unknown")
                break
              done
            ''}

            case "$CURRENT_MODE" in
              "intel")
                ICON="iGPU"
                CLASS="intel"
                TOOLTIP="Intel Mode: $INTEL_GPU\nNVIDIA runtime: $NVIDIA_STATE"
                ;;
              "nvidia")
                ICON="dGPU"
                CLASS="nvidia"
                ${lib.optionalString (cfg.type == "nvidia") ''
                  TOOLTIP="NVIDIA Mode: $NVIDIA_GPU\nRuntime: $NVIDIA_STATE"
                ''}
                ;;
              "performance")
                ICON="GPU+"
                CLASS="performance"
                ${lib.optionalString (cfg.type == "nvidia") ''
                  TOOLTIP="Performance Mode: Auto-GPU Selection\nNVIDIA runtime: $NVIDIA_STATE"
                ''}
                ;;
              *)
                ICON="iGPU"
                CLASS="intel"
                TOOLTIP="Intel Mode (Default): $INTEL_GPU\nNVIDIA runtime: $NVIDIA_STATE"
                ;;
            esac

            echo "{\"text\": \"$ICON\", \"class\": \"$CLASS\", \"tooltip\": \"$TOOLTIP\"}"
          '')
        ];
      })
    ]
  );
}
