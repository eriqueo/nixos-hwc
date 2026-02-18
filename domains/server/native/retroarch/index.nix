{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.native.retroarch;

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
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

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
        assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
        message = "hwc.server.native.retroarch.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
      }
      {
        assertion = !(cfg.sunshine.enable && !cfg.gpu.enable);
        message = "Sunshine streaming requires GPU acceleration (hwc.server.native.retroarch.gpu.enable = true)";
      }
    ];
  };
}
