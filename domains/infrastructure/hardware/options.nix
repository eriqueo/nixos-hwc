# domains/infrastructure/hardware/options.nix
#
# Consolidated options for infrastructure hardware subdomain
# Charter-compliant: ALL hardware options defined here, implementations in parts/

{ lib, config, pkgs, ... }:

let
  t = lib.types;
  cfg = config.hwc.infrastructure.hardware;

  # Helper for GPU accel derivation
  accelFor = type:
    if type == "nvidia" then "cuda"
    else if type == "amd" then "rocm"
    else if type == "intel" then "intel"
    else "cpu";
in
{
  options.hwc.infrastructure.hardware = {

    #==========================================================================
    # GPU - Hardware acceleration
    #==========================================================================
    gpu = {
      enable = lib.mkEnableOption "GPU hardware acceleration support";

      type = lib.mkOption {
        type = t.enum [ "none" "nvidia" "intel" "amd" ];
        default = "none";
        description = "GPU type for hardware acceleration";
      };

      accel = lib.mkOption {
        type = t.enum [ "cuda" "rocm" "intel" "cpu" ];
        default = accelFor cfg.gpu.type;
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
          default = cfg.gpu.type == "nvidia";
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
          default = cfg.gpu.type == "intel";
          description = "Enable Intel GPU support (auto-enabled when type = intel).";
        };
      };

      containerOptions = lib.mkOption {
        type = t.listOf t.str;
        default =
          if cfg.gpu.type == "nvidia" then [
            "--device=/dev/nvidia0:/dev/nvidia0:rwm"
            "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
            "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
            "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
            "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
            "--device=/dev/dri:/dev/dri:rwm"
          ] else if cfg.gpu.type == "intel" then [
            "--device=/dev/dri:/dev/dri"
          ] else if cfg.gpu.type == "amd" then [
            "--device=/dev/dri:/dev/dri"
          ] else [];
        description = "Container CLI device flags for GPU access (auto-generated).";
      };

      containerEnvironment = lib.mkOption {
        type = t.attrsOf t.str;
        default =
          if cfg.gpu.type == "nvidia" then {
            NVIDIA_VISIBLE_DEVICES = "all";
            NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
          } else {};
        description = "Container env vars for GPU access (auto-generated).";
      };
    };

    #==========================================================================
    # PERIPHERALS - Printing support
    #==========================================================================
    peripherals = {
      enable = lib.mkEnableOption "CUPS printing support with drivers";

      drivers = lib.mkOption {
        type = t.listOf t.package;
        default = with pkgs; [
          gutenprint     # High quality drivers for Canon, Epson, Lexmark, Sony, Olympus
          hplip          # HP Linux Imaging and Printing
          brlaser        # Brother laser printer driver
          brgenml1lpr    # Brother Generic LPR driver
          cnijfilter2    # Canon IJ Printer Driver
        ];
        description = "Printer driver packages to install";
      };

      avahi = lib.mkEnableOption "Avahi for network printer discovery";

      guiTools = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Install GUI printer management tools";
      };
    };

    #==========================================================================
    # VIRTUALIZATION - VMs and containers
    #==========================================================================
    virtualization = {
      enable = lib.mkEnableOption "QEMU/KVM virtualization with libvirtd";
      enableGpu = lib.mkEnableOption "GPU passthrough support (placeholder toggles)";
      spiceSupport = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable SPICE USB redirection and tools";
      };

      userGroups = lib.mkOption {
        type = t.listOf t.str;
        default = [ "libvirtd" ];
        description = "Groups to add primary user to for VM management";
      };
    };

    #==========================================================================
    # STORAGE - Storage tiers and external drives
    #==========================================================================
    storage = {
      hot = {
        enable = lib.mkEnableOption "Hot storage tier";

        path = lib.mkOption {
          type = t.path;
          default = "/mnt/hot";
          description = "Hot storage mount point";
        };

        device = lib.mkOption {
          type = t.str;
          default = "/dev/disk/by-uuid/YOUR-UUID-HERE";
          description = "Device UUID";
        };

        fsType = lib.mkOption {
          type = t.str;
          default = "ext4";
          description = "Filesystem type";
        };
      };

      media = {
        enable = lib.mkEnableOption "Media storage";

        path = lib.mkOption {
          type = t.path;
          default = "/mnt/media";
          description = "Media storage mount point";
        };

        directories = lib.mkOption {
          type = t.listOf t.str;
          default = [
            "movies" "tv" "music" "books" "photos"
            "downloads" "incomplete" "blackhole"
          ];
          description = "Media subdirectories to create";
        };
      };

      backup = {
        enable = lib.mkEnableOption "Backup storage infrastructure";

        path = lib.mkOption {
          type = t.path;
          default = "/mnt/backup";
          description = "Backup storage mount point";
        };

        externalDrive = {
          autoMount = lib.mkEnableOption "automatic external drive mounting for backups";

          label = lib.mkOption {
            type = t.str;
            default = "BACKUP";
            description = "Expected filesystem label for backup drives";
          };

          fsTypes = lib.mkOption {
            type = t.listOf t.str;
            default = [ "ext4" "ntfs" "exfat" "vfat" ];
            description = "Supported filesystem types for external drives";
          };

          mountOptions = lib.mkOption {
            type = t.listOf t.str;
            default = [ "defaults" "noatime" "user" "exec" ];
            description = "Mount options for external drives";
          };

          notificationUser = lib.mkOption {
            type = t.nullOr t.str;
            default = config.hwc.system.users.user.name or null;
            description = "User to notify when drives are mounted/unmounted";
          };
        };
      };
    };

    #==========================================================================
    # PERMISSIONS - User hardware access
    #==========================================================================
    permissions = {
      enable = lib.mkEnableOption "user hardware access permissions and system setup";

      username = lib.mkOption {
        type = t.str;
        default = config.hwc.system.users.user.name or "eric";
        description = "Username for hardware access setup";
      };

      groups = {
        media = lib.mkEnableOption "media hardware groups (video, audio, render)";
        development = lib.mkEnableOption "development groups (docker, podman)";
        virtualization = lib.mkEnableOption "virtualization groups (libvirtd, kvm)";
        hardware = lib.mkEnableOption "hardware access groups (input, uucp, dialout)";
      };
    };
  };
}