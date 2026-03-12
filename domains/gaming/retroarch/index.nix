{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.gaming.retroarch;

  # RetroArch with selected cores
  retroarchWithCores = pkgs.retroarch.withCores (cores:
    lib.filter (x: x != null) [
      (if cfg.cores.dosbox-pure then cores.dosbox-pure else null)
      (if cfg.cores.snes9x then cores.snes9x else null)
      (if cfg.cores.mgba then cores.mgba else null)
      (if cfg.cores.mupen64plus then cores.mupen64plus else null)
      (if cfg.cores.genesis-plus-gx then cores.genesis-plus-gx else null)
      (if cfg.cores.nestopia then cores.nestopia else null)
      (if cfg.cores.beetle-psx-hw then cores.beetle-psx-hw else null)
      (if cfg.cores.flycast then cores.flycast else null)
    ]
  );
in
{
  # OPTIONS
  options.hwc.gaming.retroarch = {
    enable = lib.mkEnableOption "RetroArch emulator with game streaming via Sunshine";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hwc/retroarch";
      description = "Directory for RetroArch configuration and data";
    };

    romsDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/media/retroarch/roms";
      description = "Directory containing ROM files";
    };

    systemDir = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/media/retroarch/system";
      description = "Directory containing BIOS and system files";
    };

    gpu = {
      enable = lib.mkEnableOption "GPU hardware acceleration for emulation and streaming";
    };

    cores = {
      # Core emulator selection - enable what you need
      dosbox-pure = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "DOSBox Pure core for DOS/Windows games";
      };

      snes9x = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Snes9x core for SNES games";
      };

      mgba = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "mGBA core for GBA games";
      };

      mupen64plus = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Mupen64Plus core for N64 games";
      };

      pcsx2 = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "PCSX2 core for PS2 games (requires beefy hardware)";
      };

      dolphin = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Dolphin core for GameCube/Wii games";
      };

      genesis-plus-gx = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Genesis Plus GX core for Sega Genesis/CD/Master System";
      };

      nestopia = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Nestopia core for NES games";
      };

      beetle-psx-hw = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Beetle PSX HW core for PlayStation games (hardware renderer)";
      };

      flycast = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Flycast core for Dreamcast games";
      };
    };

    sunshine = {
      enable = lib.mkEnableOption "Sunshine game streaming server (Moonlight compatible)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 47989;
        description = "Web UI port for Sunshine";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open firewall ports for Sunshine streaming";
      };

      capSysAdmin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable CAP_SYS_ADMIN for mouse/keyboard emulation";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall ports for RetroArch netplay";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install RetroArch with cores system-wide
    environment.systemPackages = [
      retroarchWithCores
      pkgs.retroarch-assets
      pkgs.libretro-shaders-slang
    ] ++ lib.optionals cfg.sunshine.enable [
      pkgs.sunshine
      pkgs.moonlight-qt  # Client for testing
    ];

    # Sunshine game streaming service
    services.sunshine = lib.mkIf cfg.sunshine.enable {
      enable = true;
      autoStart = true;
      capSysAdmin = cfg.sunshine.capSysAdmin;
      openFirewall = cfg.sunshine.openFirewall;
    };

    # RetroArch data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 eric users -"
      "d ${cfg.dataDir}/config 0755 eric users -"
      "d ${cfg.dataDir}/saves 0755 eric users -"
      "d ${cfg.dataDir}/states 0755 eric users -"
      "d ${cfg.dataDir}/screenshots 0755 eric users -"
      "d ${cfg.dataDir}/system 0755 eric users -"
      "d ${cfg.dataDir}/playlists 0755 eric users -"
      "d ${cfg.dataDir}/thumbnails 0755 eric users -"
    ];

    # Firewall configuration for RetroArch netplay
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 55435 ];  # RetroArch netplay
      allowedUDPPorts = [ 55435 ];
    };

    # GPU access for hardware-accelerated emulation
    # This allows RetroArch and Sunshine to use GPU rendering
    hardware.graphics = lib.mkIf cfg.gpu.enable {
      enable = true;
      enable32Bit = true;  # For 32-bit cores/games
    };

    # Ensure user has video group access for GPU
    users.users.eric.extraGroups = lib.mkIf cfg.gpu.enable [
      "video"
      "render"
      "input"  # For controller access
    ];

    # udev rules for game controllers
    services.udev.extraRules = ''
      # Xbox controllers
      SUBSYSTEM=="usb", ATTR{idVendor}=="045e", MODE="0666"
      # PlayStation controllers
      SUBSYSTEM=="usb", ATTR{idVendor}=="054c", MODE="0666"
      # Nintendo controllers
      SUBSYSTEM=="usb", ATTR{idVendor}=="057e", MODE="0666"
      # Generic HID gamepads
      KERNEL=="hidraw*", ATTRS{idVendor}=="045e", MODE="0666"
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", MODE="0666"
      KERNEL=="hidraw*", ATTRS{idVendor}=="057e", MODE="0666"
    '';

    # Sunshine user service enhancements for GPU access
    # NOTE: Sunshine runs as a user service (systemd.user.services), not a system service
    systemd.user.services.sunshine = lib.mkIf (cfg.sunshine.enable && cfg.gpu.enable) {
      environment = {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility,graphics";
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.gpu.enable || config.hwc.system.hardware.gpu.enable;
        message = "hwc.gaming.retroarch.gpu requires hwc.system.hardware.gpu.enable = true";
      }
      {
        assertion = !(cfg.sunshine.enable && !cfg.gpu.enable);
        message = "Sunshine streaming requires GPU acceleration (hwc.gaming.retroarch.gpu.enable = true)";
      }
    ];
  };
}
