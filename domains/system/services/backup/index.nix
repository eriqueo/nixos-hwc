# domains/system/services/backup/index.nix
#
# BACKUP - System-wide backup service and tools.
# This file aggregates the module's components and defines its core packages.
# Supports local backups (external drives, NAS, DAS) and cloud backups (Proton Drive).

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.backup;
in
{
  #=========================================================================
  # MODULE AGGREGATION
  #=========================================================================
  # This file assembles the backup module by importing its API (options)
  # and its implementation logic (parts).
  imports = [
    ./options.nix
    ./parts/local-backup.nix
    ./parts/cloud-backup.nix
    ./parts/backup-utils.nix
    ./parts/backup-scheduler.nix
  ];

  #=========================================================================
  # CO-LOCATED PACKAGES
  #=========================================================================
  # This is the single source of truth for all packages required by this module.
  # The parts files can then assume these packages are available.
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Core backup tools
      rclone        # Cloud sync (Proton Drive, etc.)
      rsync         # Incremental local backups
      gnutar        # Archive creation
      gzip          # Compression
      bzip2         # Compression
      p7zip         # Archive support
      logrotate     # Log management

      # Utilities for scripts
      findutils     # find command
      coreutils     # Basic utilities
      util-linux    # mountpoint, etc.
      gawk          # Text processing
      gnused        # Stream editor
      gnugrep       # Grep
      nettools      # hostname
      libnotify     # Desktop notifications
    ]
    # Add any extra tools defined on a per-machine basis.
    ++ cfg.extraTools;

    # Warnings
    warnings = lib.optionals (!cfg.local.enable && !cfg.cloud.enable) [
      "Backup service is enabled but no backup methods (local or cloud) are configured"
    ];
  };
}
