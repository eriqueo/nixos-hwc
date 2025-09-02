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
       options.hwc.home.apps = {
         enable = lib.mkEnableOption "Desktop applications";

         browser = {
           firefox = lib.mkEnableOption "Firefox browser";
           chromium = lib.mkEnableOption "Chromium browser";
         };

         multimedia = {
           enable = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable multimedia applications";
           };
         };

         productivity = {
           enable = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable productivity applications";
           };
         };
       };


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
           thunderbird
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
