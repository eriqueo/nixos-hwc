# nixos-hwc/modules/home/waybar/default.nix
#
# WAYBAR - Wayland status bar configuration (Complete UI restoration)
# Preserves 100% functionality from /etc/nixos/hosts/laptop/modules/waybar.nix monolith
#
# DEPENDENCIES (Upstream):
#   - ./system.nix (provides all 13 tools)
 
#   - Home-Manager programs.waybar support
#
# USED BY (Downstream):
#   - profiles/workstation.nix (imports via home-manager)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../modules/home/waybar/default.nix
#
# USAGE:
#   home-manager.users.<name>.imports = [ ../modules/home/waybar/default.nix ];

{ config, lib, pkgs, nixosConfig, ... }:

   
let
 
in {
 imports = [
    ./parts/home.nix ];

 

 }
