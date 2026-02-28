# domains/system/hardware/gpu/options.nix
# GPU hardware acceleration options

{ lib, config, pkgs, ... }:

let
  t = lib.types;
  cfg = config.hwc.system.hardware.gpu;

  accelFor = type:
    if type == "nvidia" then "cuda"
    else if type == "amd" then "rocm"
    else if type == "intel" then "intel"
    else "cpu";
in
{
  options.hwc.system.hardware.gpu = {

    enable = lib.mkEnableOption "GPU hardware acceleration support";

    type = lib.mkOption {
      type = t.enum [ "none" "nvidia" "intel" "amd" ];
      default = "none";
      description = "GPU type for hardware acceleration";
    };

    accel = lib.mkOption {
      type = t.enum [ "cuda" "rocm" "intel" "cpu" ];
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
}
