# HWC Charter Module/domains/home/apps/thunar.nix
# ... (header is the same)

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.thunar;
in
{
  imports = [ ./options.nix ];
  #============================================================================
  # IMPLEMENTATION - Thunar file manager configuration
  #============================================================================
  config = {
    #==========================================================================
    # UNCONDITIONAL DESKTOP ENTRY
    # This is always defined, fixing the "no value defined" error.
    #==========================================================================
    xdg.desktopEntries.micro = {
      name = "Micro Text Editor";
      comment = "Edit text files with micro in kitty terminal";
      exec = "kitty micro %F";
      icon = "text-editor";
      mimeType = [ "text/plain" "application/x-shellscript" ];
      categories = [ "TextEditor" "Development" "ConsoleOnly" ];
    };

    #==========================================================================
    # CONDITIONAL THUNAR CONFIGURATION
    # These settings are only merged if `hwc.home.apps.thunar.enable` is true.
    #==========================================================================
    home.packages = lib.mkIf cfg.enable (with pkgs; [
      xfce.thunar
      xfce.thunar-volman
      xfce.thunar-archive-plugin
      xfce.thunar-media-tags-plugin
      gvfs
      udisks2
      shared-mime-info
      desktop-file-utils
      file-roller
      xfce.tumbler
      ffmpegthumbnailer
      trash-cli
    ]);

    xdg.mimeApps = lib.mkIf cfg.enable {
      enable = true;
      defaultApplications = {
        "inode/directory" = [ "thunar.desktop" ];
        "application/x-directory" = [ "thunar.desktop" ];
        "application/zip" = [ "file-roller.desktop" ];
        "application/x-tar" = [ "file-roller.desktop" ];
        "application/x-compressed-tar" = [ "file-roller.desktop" ];
        "application/x-bzip-compressed-tar" = [ "file-roller.desktop" ];
        "application/x-xz-compressed-tar" = [ "file-roller.desktop" ];
        "application/x-7z-compressed" = [ "file-roller.desktop" ];
        "application/x-rar" = [ "file-roller.desktop" ];
        "text/*" = [ "micro.desktop" ];
        "application/x-*" = [ "micro.desktop" ];
        "application/json" = [ "micro.desktop" ];
        "application/xml" = [ "micro.desktop" ];
        "application/yaml" = [ "micro.desktop" ];
      };
    };

    home.sessionVariables = lib.mkIf cfg.enable {
      FILE_MANAGER = "thunar";
      TERMINAL = "kitty";
    };

    xdg.configFile."xfce4/helpers.rc" = lib.mkIf cfg.enable {
      text = ''
        TerminalEmulator=kitty
      '';
    };
  };
}
