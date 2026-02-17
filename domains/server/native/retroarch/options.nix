{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hwc.server.native.retroarch = {
    enable = mkEnableOption "RetroArch emulator with game streaming via Sunshine";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/hwc/retroarch";
      description = "Directory for RetroArch configuration and data";
    };

    romsDir = mkOption {
      type = types.path;
      default = "/mnt/ext/retroarch/roms";
      description = "Directory containing ROM files";
    };

    gpu = {
      enable = mkEnableOption "GPU hardware acceleration for emulation and streaming";
    };

    cores = {
      # Core emulator selection - enable what you need
      dosbox-pure = mkOption {
        type = types.bool;
        default = true;
        description = "DOSBox Pure core for DOS/Windows games";
      };

      snes9x = mkOption {
        type = types.bool;
        default = true;
        description = "Snes9x core for SNES games";
      };

      mgba = mkOption {
        type = types.bool;
        default = true;
        description = "mGBA core for GBA games";
      };

      mupen64plus = mkOption {
        type = types.bool;
        default = true;
        description = "Mupen64Plus core for N64 games";
      };

      pcsx2 = mkOption {
        type = types.bool;
        default = false;
        description = "PCSX2 core for PS2 games (requires beefy hardware)";
      };

      dolphin = mkOption {
        type = types.bool;
        default = false;
        description = "Dolphin core for GameCube/Wii games";
      };

      genesis-plus-gx = mkOption {
        type = types.bool;
        default = true;
        description = "Genesis Plus GX core for Sega Genesis/CD/Master System";
      };

      nestopia = mkOption {
        type = types.bool;
        default = true;
        description = "Nestopia core for NES games";
      };

      beetle-psx-hw = mkOption {
        type = types.bool;
        default = true;
        description = "Beetle PSX HW core for PlayStation games (hardware renderer)";
      };

      flycast = mkOption {
        type = types.bool;
        default = true;
        description = "Flycast core for Dreamcast games";
      };
    };

    sunshine = {
      enable = mkEnableOption "Sunshine game streaming server (Moonlight compatible)";

      port = mkOption {
        type = types.port;
        default = 47989;
        description = "Web UI port for Sunshine";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open firewall ports for Sunshine streaming";
      };

      capSysAdmin = mkOption {
        type = types.bool;
        default = true;
        description = "Enable CAP_SYS_ADMIN for mouse/keyboard emulation";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open firewall ports for RetroArch netplay";
    };
  };
}
