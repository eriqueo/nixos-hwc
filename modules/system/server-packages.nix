# nixos-hwc/modules/system/server-packages.nix
#
# SERVER PACKAGES - System-level packages for server operations
# GUI applications for X11 forwarding and server-specific tools
#
# DEPENDENCIES (Upstream):
#   - None (base system packages)
#
# USED BY (Downstream):
#   - machines/server/config.nix (enables via hwc.system.serverPackages.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../modules/system/server-packages.nix
#
# USAGE:
#   hwc.system.serverPackages.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.serverPackages;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.system.serverPackages = {
    enable = lib.mkEnableOption "Server-specific system packages";
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Server-specific system packages
    environment.systemPackages = with pkgs; [
      # GUI applications (X11 forwarding support)
      kitty                  # Terminal emulator
      xfce.thunar           # File manager
      xorg.xauth            # Required for X11 forwarding
      file-roller           # Archive manager
      evince                # PDF viewer
      feh                   # Image viewer
      
      # Media tools (server-specific)
      picard                # Music organization
      
      # Server monitoring and management
      htop iotop
      lsof net-tools iproute2
      tcpdump nmap
      
      # Container management
      docker-compose
      podman-compose
      
      # File management for media
      rsync rclone
      unzip p7zip
      
      # Database tools
      postgresql  # Client tools
      redis       # CLI tools
      
      # Media processing
      ffmpeg imagemagick
      
      # AI/ML tools (basic)
      python3
      
      # Backup and archival
      borgbackup restic
    ];
  };
}