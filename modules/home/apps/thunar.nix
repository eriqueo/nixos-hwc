# nixos-hwc/modules/home/apps/thunar.nix
#
# THUNAR FILE MANAGER - File manager configuration with theme integration
# Charter v6 compliant - Single-file app config with proper theming
#
# DEPENDENCIES (Upstream):
#   - Home Manager modules system
#   - GTK theming system (inherits automatically)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (imports this module)
#   - modules/home/apps/hyprland/parts/behavior.nix (SUPER+1 keybinding)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: home-manager.users.eric.imports = [ ../modules/home/apps/thunar.nix ]
#
# USAGE:
#   # Thunar enabled automatically when imported (package installation)

{ config, lib, pkgs, ... }:

{
  #============================================================================
  # IMPLEMENTATION - Thunar file manager configuration
  #============================================================================
  
  # Thunar package provided by system base-packages.nix
  # Install essential plugins and supporting tools
  home.packages = with pkgs; [
    # Essential plugins for functionality
    xfce.thunar-volman       # Volume management
    xfce.thunar-archive-plugin  # Archive handling (.zip, .tar.gz, etc.)
    xfce.thunar-media-tags-plugin  # Media file tags
    
    # File operations support
    gvfs                     # Virtual filesystems (trash, network, etc.)
    udisks2                  # Disk mounting
    
    # Archive support
    file-roller              # Archive manager integration
    
    # Image thumbnails
    xfce.tumbler                  # Thumbnail service for images/videos
    ffmpegthumbnailer       # Video thumbnails
    
    # Additional file operations
    trash-cli               # Command-line trash operations
  ];
  
  # GTK configuration for file manager appearance
  # Note: Thunar uses GTK theming, so it inherits from system GTK theme
  gtk = {
    enable = true;
    
    # File chooser settings
    gtk3.extraConfig = {
      gtk-recent-files-max-age = 30;  # Keep recent files for 30 days
      gtk-recent-files-enabled = true;
    };
  };
  
  # XDG MIME associations for file types
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Make Thunar the default file manager
      "inode/directory" = [ "thunar.desktop" ];
      "application/x-directory" = [ "thunar.desktop" ];
      
      # Archive file associations
      "application/zip" = [ "file-roller.desktop" ];
      "application/x-tar" = [ "file-roller.desktop" ];
      "application/x-compressed-tar" = [ "file-roller.desktop" ];
      "application/x-bzip-compressed-tar" = [ "file-roller.desktop" ];
      "application/x-xz-compressed-tar" = [ "file-roller.desktop" ];
      "application/x-7z-compressed" = [ "file-roller.desktop" ];
      "application/x-rar" = [ "file-roller.desktop" ];
    };
  };
  
  # Services for file manager integration
  # Note: tumbler and trash-cli are packages only, no Home Manager services needed
  
  # Session variables for file manager behavior
  home.sessionVariables = {
    # Set Thunar as default file manager for applications
    FILE_MANAGER = "thunar";
    # Set terminal for Thunar to use when opening "Open in Terminal"
    TERMINAL = "kitty";
  };

  # XDG configuration for default applications
  xdg.configFile."xfce4/helpers.rc".text = ''
    TerminalEmulator=kitty
  '';
}
