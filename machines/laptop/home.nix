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
    
    users.eric = { config, pkgs, ... }: {
      imports = [
        # Core user configuration
        ../../modules/home/core/eric.nix
        
        # Shell and environment
        ../../modules/home/environment/shell.nix
        ../../modules/home/environment/git.nix
        
        # Desktop environment
        ../../modules/home/apps/hyprland
        ../../modules/home/apps/waybar
        ../../modules/home/apps/wofi
        ../../modules/home/apps/kitty
        ../../modules/home/apps/thunar
        
        # Development tools
        ../../modules/home/dev/neovim
        ../../modules/home/dev/vscode
        
        # Productivity apps
        ../../modules/home/apps/firefox
        ../../modules/home/apps/discord
        ../../modules/home/apps/spotify
        ../../modules/home/apps/obsidian
      ];
      
      # Home Manager state version
      home.stateVersion = "24.05";
      
      # Machine-specific home configuration can go here
      # (Currently none needed)
    };
  };
}