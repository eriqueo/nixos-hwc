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

    # Create directory structure and seed config files
    home.activation.retroarchSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
      # Create directories
      $DRY_RUN_CMD mkdir -p ${cfg.romPath}
      $DRY_RUN_CMD mkdir -p ${cfg.saveStatePath}/states
      $DRY_RUN_CMD mkdir -p ${cfg.saveStatePath}/saves
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/assets
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/database
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/shaders
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/cheats
      $DRY_RUN_CMD mkdir -p ~/.config/retroarch/autoconfig/udev

      # Seed retroarch.cfg if it doesn't exist (or is a symlink from old config)
      if [ ! -f ~/.config/retroarch/retroarch.cfg ] || [ -L ~/.config/retroarch/retroarch.cfg ]; then
        $DRY_RUN_CMD rm -f ~/.config/retroarch/retroarch.cfg
        $DRY_RUN_CMD cp ${./files/retroarch-base.cfg} ~/.config/retroarch/retroarch.cfg
        $DRY_RUN_CMD chmod 644 ~/.config/retroarch/retroarch.cfg
        echo "Seeded RetroArch config from template"
      fi

      # Seed Joy-Con autoconfigs if they don't exist (or are symlinks)
      if [ ! -f ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Combined_Joy-Cons.cfg ] || \
         [ -L ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Combined_Joy-Cons.cfg ]; then
        $DRY_RUN_CMD rm -f ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Combined_Joy-Cons.cfg
        $DRY_RUN_CMD cp ${./files/Nintendo_Switch_Combined_Joy-Cons.cfg} \
          ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Combined_Joy-Cons.cfg
        $DRY_RUN_CMD chmod 644 ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Combined_Joy-Cons.cfg
        echo "Seeded Combined Joy-Cons autoconfig"
      fi

      if [ ! -f ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Left_Joy-Con.cfg ] || \
         [ -L ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Left_Joy-Con.cfg ]; then
        $DRY_RUN_CMD rm -f ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Left_Joy-Con.cfg
        $DRY_RUN_CMD cp ${./files/Nintendo_Switch_Left_Joy-Con.cfg} \
          ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Left_Joy-Con.cfg
        $DRY_RUN_CMD chmod 644 ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Left_Joy-Con.cfg
        echo "Seeded Left Joy-Con autoconfig"
      fi

      if [ ! -f ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Right_Joy-Con.cfg ] || \
         [ -L ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Right_Joy-Con.cfg ]; then
        $DRY_RUN_CMD rm -f ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Right_Joy-Con.cfg
        $DRY_RUN_CMD cp ${./files/Nintendo_Switch_Right_Joy-Con.cfg} \
          ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Right_Joy-Con.cfg
        $DRY_RUN_CMD chmod 644 ~/.config/retroarch/autoconfig/udev/Nintendo_Switch_Right_Joy-Con.cfg
        echo "Seeded Right Joy-Con autoconfig"
      fi
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
