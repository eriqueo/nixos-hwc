# domains/home/apps/retroarch/index.nix
#
# MODULE: RetroArch
# Home Manager configuration for RetroArch multi-platform emulator frontend
#
# NAMESPACE: hwc.home.apps.retroarch.*
#
# DEPENDENCIES:
#   Upstream: None (standalone HM module)
#
# USED BY:
#   Downstream: machines/*/home.nix (selective import)
#
# USAGE:
#   hwc.home.apps.retroarch = {
#     enable = true;
#     cores = [ "snes9x" "genesis-plus-gx" "beetle-psx-hw" ];
#     theme = "ozone";
#     romPath = "~/retro-roms";
#   };
#
# CHARTER:
#   - Domain: home (HM user environment)
#   - Lane: HM only (sys.nix imported separately by system profiles)
#   - Unit anatomy: options.nix, index.nix, sys.nix, parts/

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.retroarch;

  # Import pure helpers
  coreHelper = import ./parts/cores.nix { inherit pkgs; };
  configHelper = import ./parts/config.nix { inherit lib cfg; };

  # Resolve core packages from user-friendly names
  corePackages = coreHelper.resolveCores cfg.cores;

  # Build RetroArch with selected cores
  # retroarch is already a wrapper function, use it directly
  retroarchWithCores = pkgs.retroarch.withCores (cores: corePackages);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    # Install RetroArch with cores and optional utilities
    home.packages = [
      retroarchWithCores
      pkgs.retroarch-assets
      pkgs.retroarch-joypad-autoconfig
    ] ++ lib.optionals cfg.enableShaders [
      pkgs.libretro-shaders-slang
    ] ++ lib.optionals (cfg.cores != []) [
      # Optional: Quick launch script example
      (pkgs.writeShellScriptBin "retroarch-snes" ''
        ${retroarchWithCores}/bin/retroarch -L ${pkgs.libretro.snes9x}/lib/retroarch/cores/snes9x_libretro.so "$@"
      '')
    ];

    # RetroArch configuration file
    home.file.".config/retroarch/retroarch.cfg" = {
      text = configHelper.generateConfig;
      # Don't force - allow user modifications to persist
      force = false;
    };

    # Create directory structure
    home.activation.retroarchDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD mkdir -p ${cfg.romPath}
      $DRY_RUN_CMD mkdir -p ${cfg.saveStatePath}/states
      $DRY_RUN_CMD mkdir -p ${cfg.saveStatePath}/saves
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/assets
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/database
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/shaders
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/cheats
    '';

    # Desktop entry for launching RetroArch
    xdg.desktopEntries.retroarch = lib.mkIf (cfg.fullscreen) {
      name = "RetroArch (Fullscreen)";
      comment = "Frontend for libretro emulation cores";
      exec = "${retroarchWithCores}/bin/retroarch --fullscreen";
      icon = "retroarch";
      terminal = false;
      categories = [ "Game" "Emulator" ];
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.cores != [];
        message = "RetroArch requires at least one core to be specified in hwc.home.apps.retroarch.cores";
      }
    ];
  };
}
