# nixos-hwc/machines/hwc-kids/home.nix
#
# HOME MANAGER ACTIVATION (Machine-Specific)
# Charter Section 7: HM activation is machine-specific, never in profiles.
#
# This file defines which home-manager modules are activated for the eric
# user on the hwc-kids machine. Modules are imported from domains/home/apps/,
# making this machine's user environment distinct from hwc-laptop.

{ config, pkgs, lib, ... }:

{
  #============================================================================
  # HOME MANAGER ACTIVATION (eric user)
  #============================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";

    users.eric = {
      #==========================================================================
      # MODULE IMPORTS - Full home domain + machine-specific apps
      #==========================================================================
      imports = [
        # Import entire home domain (shell, fonts, theme, etc.)
        ../../domains/home/index.nix

        # Machine-specific: Retro gaming (NOT on laptop)
        ../../domains/home/apps/retroarch
      ];

      #==========================================================================
      # MODULE CONFIGURATION
      #==========================================================================

      # Shell configuration (same as laptop)
      hwc.home.shell = {
        enable = true;
        modernUnix = true;
        git.enable = true;
        zsh = {
          enable = true;
          starship = true;
          autosuggestions = true;
          syntaxHighlighting = true;
        };
      };

      # Theme and fonts
      hwc.home.theme.palette = "gruv";
      hwc.home.fonts.enable = true;

      # Desktop Environment - Hyprland compositor + tools
      hwc.home.apps.hyprland.enable = true;
      hwc.home.apps.waybar.enable = true;
      hwc.home.apps.kitty.enable = true;
      hwc.home.apps.thunar.enable = true;
      hwc.home.apps.dunst.enable = true;

      # Browsers
      hwc.home.apps.chromium.enable = true;
      hwc.home.apps.librewolf.enable = true;

      # Productivity
      hwc.home.apps.obsidian.enable = true;
      hwc.home.apps.onlyofficeDesktopeditors.enable = true;
      hwc.home.apps.wasistlos.enable = true;

      # Mail & Communication
      hwc.home.apps.betterbird.enable = true;
      hwc.home.apps.protonAuthenticator.enable = true;
      hwc.home.apps.protonMail.enable = true;
      hwc.home.apps.aerc.enable = true;
      hwc.home.apps.neomutt.enable = true;
      hwc.home.apps.neomutt.theme.palette = "gruv";

      # Mail system configuration
      hwc.home.mail = {
        enable = true;
        # Optional overrides for Bridge (defaults are fine to omit)
        # bridge = {
        #   enable = true;        # defaults to true when a proton account exists
        #   logLevel = "warn";    # "error" | "warn" | "info" | "debug"
        #   extraArgs = [ ];
        #   environment = { };
        # };
      };

      # Utilities
      hwc.home.apps.yazi.enable = true;
      hwc.home.apps.ipcalc.enable = true;
      hwc.home.apps.geminiCli.enable = true;
      hwc.home.apps.n8n.enable = true;

      # PC Emulation
      hwc.home.apps._86box = {
        enable = true;
        withRoms = true;  # Include ROM files for easier setup
      };
      hwc.home.apps.dosbox.enable = true;

      # RetroArch configuration (hwc-kids specific)
      hwc.home.apps.retroarch = {
        enable = true;

        # Emulation cores for retro systems
        cores = [
          # Nintendo
          "snes9x"           # Super Nintendo
          "nestopia"         # NES
          "mupen64plus"      # N64
          "mgba"             # Game Boy Advance
          "gambatte"         # Game Boy / Game Boy Color

          # Sega
          "genesis-plus-gx"  # Genesis / Mega Drive / Master System

          # Sony
          "beetle-psx-hw"    # PlayStation 1

          # Arcade
          "mame2003-plus"    # MAME (2003 romset)
          "fbneo"            # FinalBurn Neo
        ];

        # UI preferences
        theme = "ozone";             # Modern UI (ozone, xmb, rgui)
        fullscreen = false;          # Launch in windowed mode by default

        # Paths
        romPath = "/home/eric/retro-roms";
        saveStatePath = "/home/eric/.config/retroarch/saves";

        # Features
        enableShaders = true;        # CRT shaders and visual filters
        enableCheats = false;        # Disable cheat database
        autoSave = true;             # Auto-save/load states
        rewindSupport = true;        # Enable rewind (uses more RAM)
        netplay = false;             # Disable network play

        # Performance
        videoDriver = "vulkan";      # Best performance on Intel GPU
        audioDriver = "pipewire";    # Modern audio stack
      };

      # Additional packages for this machine
      home.packages = with pkgs; [
        qbittorrent  # BitTorrent client
      ];

      #==========================================================================
      # HOME MANAGER STATE VERSION
      #==========================================================================
      home.stateVersion = "24.05";
    };
  };
}
