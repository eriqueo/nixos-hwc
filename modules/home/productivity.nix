{ config, lib, pkgs, ... }:
     let
       cfg = config.hwc.home.productivity;
     in {
       options.hwc.home.productivity = {
         enable = lib.mkEnableOption "Productivity applications";

         notes = {
           obsidian = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Obsidian note-taking";
           };
         };

         browsers = {
           firefox = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Firefox browser";
           };
           chromium = lib.mkOption {
             type = lib.types.bool;
             default = false;
             description = "Enable Chromium browser";
           };
         };

         office = {
           libreoffice = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable LibreOffice suite";
           };
         };

         communication = {
           thunderbird = lib.mkOption {
             type = lib.types.bool;
             default = true;
             description = "Enable Thunderbird email client";
           };
           discord = lib.mkOption {
             type = lib.types.bool;
             default = false;
             description = "Enable Discord";
           };
         };
       };

       config = lib.mkIf cfg.enable {

         environment.systemPackages = with pkgs; [
           # Notes
         ] ++ lib.optionals cfg.notes.obsidian [
           obsidian
         ] ++ lib.optionals cfg.browsers.chromium [
           chromium
         ] ++ lib.optionals cfg.browsers.firefox [
          firefox
         ] ++ lib.optionals cfg.office.libreoffice [
           libreoffice
         ] ++ lib.optionals cfg.communication.thunderbird [
           thunderbird
         ] ++ lib.optionals cfg.communication.discord [
           discord
         ];

         # File manager
         programs.thunar.enable = true;

         # Archive support
         programs.file-roller.enable = true;
       };
     }
