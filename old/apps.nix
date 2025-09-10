# nixos-hwc/modules/home/apps.nix
#
# APPS - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.home.apps.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/home/apps.nix
#
# USAGE:
#   hwc.home.apps.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
     let
       cfg = config.hwc.home.apps;
     in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  # NOTE: Options moved to /modules/home/apps/default.nix to avoid conflicts


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
       config = lib.mkIf cfg.enable {
         # Browsers
         programs.firefox.enable = cfg.browser.firefox;

         environment.systemPackages = with pkgs; [
           # Browsers
         ] ++ lib.optionals cfg.browser.chromium [
           chromium
         ] ++ lib.optionals cfg.multimedia.enable [
           # Multimedia
           vlc
           mpv
           pavucontrol
           obs-studio
         ] ++ lib.optionals cfg.productivity.enable [
           # Productivity
           obsidian
           libreoffice
           # thunderbird - now managed by modules/home/betterbird
         ];

         # XDG portal for file dialogs
         xdg.portal = {
           enable = true;
           wlr.enable = true;
           extraPortals = with pkgs; [
             xdg-desktop-portal-gtk
           ];
         };

         # Font configuration
         fonts.packages = with pkgs; [
           jetbrains-mono
           nerd-fonts.jetbrains-mono
           fira-code
           font-awesome
         ];
       };
     }
