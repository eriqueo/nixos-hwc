# domains/system/packages/server.nix
# SERVER PACKAGES - System-level packages for server operations
# Charter-compliant: implementation only, options in packages/options.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.packages.server;
in {
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Server-specific system packages
    environment.systemPackages = with pkgs; [
      # GUI applications (X11 forwarding support)
      # kitty and thunar moved to base-packages.nix (universal tools)
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

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}