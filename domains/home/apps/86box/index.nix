# domains/home/apps/86box/index.nix
#
# 86BOX - PC Emulator (8086 through Pentium II era)
# Full PC emulation for running DOS, Windows 3.x, 95, 98, ME, 2000, XP
#
# DEPENDENCIES (Upstream):
#   - domains/home/apps/86box/options.nix (API definition)
#
# USED BY (Downstream):
#   - machines/hwc-kids/home.nix (gaming machine)
#
# USAGE:
#   hwc.home.apps._86box.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps._86box;

  # Auto-select package based on ROM preference
  selectedPackage =
    if cfg.package != null then cfg.package
    else if cfg.withRoms then pkgs._86Box-with-roms
    else pkgs._86Box;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [
    ./options.nix
  ];

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ selectedPackage ];

    # Create default config directory structure
    home.file."${cfg.configDir}/.keep".text = "";

    # Optional: Add desktop entry customization
    xdg.desktopEntries."86Box" = lib.mkIf cfg.withRoms {
      name = "86Box";
      genericName = "PC Emulator";
      comment = "Emulator of x86-based machines (8086 through Pentium II)";
      exec = "86Box";
      icon = "86Box";
      categories = [ "Game" "Emulator" ];
      terminal = false;
    };
  };

  #============================================================================
  # VALIDATION
  #============================================================================
  # No assertions needed for this module
}
