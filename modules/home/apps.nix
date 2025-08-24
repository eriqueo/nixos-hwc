{ config, lib, pkgs, ... }:
     let
       cfg = config.hwc.desktop.apps;
     in {
       options.hwc.desktop.apps = {
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
