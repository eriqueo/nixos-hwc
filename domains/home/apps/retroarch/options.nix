{ lib, ... }:

{
  options.hwc.home.apps.retroarch = {
    enable = lib.mkEnableOption "RetroArch multi-platform emulator frontend";

    cores = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "snes9x" "genesis-plus-gx" "beetle-psx-hw" "mupen64plus" ];
      description = ''
        List of libretro cores to install with RetroArch.
        Available cores include: snes9x, genesis-plus-gx, beetle-psx-hw,
        mupen64plus, mgba, nestopia, mesen, dolphin, pcsx2, and many more.
        See pkgs.libretro for full list.
      '';
    };

    theme = lib.mkOption {
      type = lib.types.enum [ "ozone" "xmb" "rgui" ];
      default = "ozone";
      description = ''
        RetroArch UI theme.
        - ozone: Modern, clean interface (default)
        - xmb: PlayStation-style cross menu bar
        - rgui: Classic retro interface
      '';
    };

    romPath = lib.mkOption {
      type = lib.types.str;
      default = "~/retro-roms";
      description = "Default path to ROM library directory";
    };

    saveStatePath = lib.mkOption {
      type = lib.types.str;
      default = "~/.config/retroarch/saves";
      description = "Path for save states and SRAM files";
    };

    enableShaders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable CRT shaders and visual filters";
    };

    enableCheats = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable cheat database support";
    };

    autoSave = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically save state on exit and load on startup";
    };

    fullscreen = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start RetroArch in fullscreen mode";
    };

    videoDriver = lib.mkOption {
      type = lib.types.enum [ "vulkan" "glcore" "gl" ];
      default = "vulkan";
      description = ''
        Video driver for RetroArch rendering.
        - vulkan: Best performance (requires GPU support)
        - glcore: OpenGL core profile
        - gl: Legacy OpenGL
      '';
    };

    audioDriver = lib.mkOption {
      type = lib.types.enum [ "pipewire" "pulse" "alsa" ];
      default = "pipewire";
      description = "Audio backend driver";
    };

    rewindSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable rewind functionality (uses extra RAM)";
    };

    netplay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable network play support";
    };
  };
}
