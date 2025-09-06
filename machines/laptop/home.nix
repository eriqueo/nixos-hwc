# nixos-hwc/machines/laptop/home.nix
#
# MACHINE: Laptop — Home Manager Activation
# Purpose: Activate Home Manager and import all user environment modules for this machine.
#
# DEPENDENCIES (Upstream):
#   - All modules/home/* modules (imported below)
#
# USED BY (Downstream):
#   - machines/laptop/config.nix (imports this file)
#
# IMPORTS REQUIRED IN:
#   - machines/laptop/config.nix: imports = [ ./home.nix ... ];
#
# CHARTER NOTES:
#   - This is where Home Manager gets activated for this specific machine
#   - All user environment configuration is imported and activated here
#   - Machine-specific home overrides can be added at the bottom

{ config, lib, pkgs, ... }:

{
  ##############################################################################
  ##  MACHINE HOME MANAGER ACTIVATION
  ##  This file activates Home Manager and imports all user environment modules
  ##############################################################################

  #============================================================================
  # HOME MANAGER ACTIVATION
  #============================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    
    users.eric = { config, lib, pkgs, ... }: {
      imports = [
        # Shell and environment
        ../../modules/home/environment/shell.nix
        ../../modules/home/environment/development.nix
        ../../modules/home/environment/productivity.nix
        # Theme
        ../../modules/home/theme/default.nix
        # Desktop environment
        ../../modules/home/apps/default.nix

      ];
      
      # Home Manager state version
      home.stateVersion = "24.05";
      
      # Single palette toggle; adapters are already loaded via theme/default.nix

      hwc.home.theme.palette = "deep-nord";
      hwc.home.apps = {
          enable = true;
          kitty.enable    = true;
          thunar.enable   = true;
          waybar.enable   = true;
          hyprland.enable = true;
        };
      # Enable complete shell environment
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
    };
  };
}
