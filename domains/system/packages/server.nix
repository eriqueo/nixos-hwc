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
      # file-roller         # Archive manager - not available in 24.05
      evince                # PDF viewer
      feh                   # Image viewer
      fping
      ethtool
      # Media tools (server-specific)
      picard                # Music organization
      # claude-code         # Not available in 24.05
      flac
      # Server monitoring and management
      htop iotop
      lsof nettools iproute2  # net-tools → nettools in 24.05
      tcpdump nmap

      # Secret management
      age  # Encryption/decryption tool for agenix secrets

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
      ffmpeg imagemagick mediainfo

      # AI/ML tools (basic)
      python3
      # aider-chat             # AI pair programming - not available in 24.05
      # gemini-cli             # Temporarily disabled due to npm cache build failure
      
      # Backup and archival
      borgbackup restic
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
