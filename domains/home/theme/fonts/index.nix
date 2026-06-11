# domains/home/theme/fonts/index.nix
# Font management for user environment

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.theme.fonts;
in {
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.theme.fonts = {
    enable = lib.mkEnableOption "Enable HWC font management for user environment";

    mono = lib.mkOption {
      type = lib.types.str;
      default = "CaskaydiaCove Nerd Font";
      description = "Monospace font family token (installed below). Consumed by kitty.";
    };

    ui = lib.mkOption {
      type = lib.types.str;
      default = "Hack Nerd Font";
      description = "UI font family token (installed below). Consumed by waybar/swaync.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = true;

    home.packages = with pkgs; [
      nerd-fonts.caskaydia-cove
      nerd-fonts.hack
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
