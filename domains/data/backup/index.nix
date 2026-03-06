# domains/data/backup/index.nix
#
# Backup domain — system-wide backup service and tools.
# Supports local backups (external drives, NAS, DAS), cloud backups (Proton Drive),
# user data backup, and server container/database backup scripts.
#
# Namespace: hwc.data.backup.*
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.data.backup;
in
{
  #==========================================================================
  # OPTIONS + PARTS
  #==========================================================================
  imports = [
    ./options.nix
    ./parts/local-backup.nix
    ./parts/cloud-backup.nix
    ./parts/backup-utils.nix
    ./parts/backup-scheduler.nix
    ./parts/database-hooks.nix
    ./parts/server-backup-scripts.nix
  ];
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      rclone
      rsync
      gnutar
      gzip
      bzip2
      p7zip
      logrotate
      findutils
      coreutils
      util-linux
      gawk
      gnused
      gnugrep
      nettools
      libnotify
    ]
    ++ cfg.extraTools;

    warnings = lib.optionals (!cfg.local.enable && !cfg.cloud.enable) [
      "Backup service is enabled but no backup methods (local or cloud) are configured"
    ];
  };
}
