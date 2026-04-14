# domains/system/services/borg/parts/scripts.nix
#
# Pure helper functions for Borg backup scripts
# These are utilities that can be imported by index.nix

{ pkgs, lib }:

{
  # Generate a borg wrapper script with passphrase from agenix
  mkBorgWrapper = { repoPath, passphraseSecret }: pkgs.writeShellScriptBin "borg-hwc" ''
    export BORG_PASSCOMMAND="cat /run/agenix/${passphraseSecret}"
    export BORG_REPO="${repoPath}"
    exec ${pkgs.borgbackup}/bin/borg "$@"
  '';

  # Script to list recent backups with size info
  mkListBackupsScript = { repoPath, passphraseSecret }: pkgs.writeShellScriptBin "borg-list-backups" ''
    export BORG_PASSCOMMAND="cat /run/agenix/${passphraseSecret}"
    echo "=== Borg Backups in ${repoPath} ==="
    ${pkgs.borgbackup}/bin/borg list --short "${repoPath}"
    echo ""
    echo "=== Repository Info ==="
    ${pkgs.borgbackup}/bin/borg info "${repoPath}"
  '';

  # Script to restore a specific archive
  mkRestoreScript = { repoPath, passphraseSecret }: pkgs.writeShellScriptBin "borg-restore" ''
    export BORG_PASSCOMMAND="cat /run/agenix/${passphraseSecret}"

    if [ $# -lt 2 ]; then
      echo "Usage: borg-restore <archive-name> <target-dir> [path-to-restore]"
      echo ""
      echo "Examples:"
      echo "  borg-restore hwc-backup-2026-02-25 /tmp/restore"
      echo "  borg-restore hwc-backup-2026-02-25 /tmp/restore home/eric/photos"
      echo ""
      echo "Available archives:"
      ${pkgs.borgbackup}/bin/borg list --short "${repoPath}"
      exit 1
    fi

    ARCHIVE="$1"
    TARGET="$2"
    SUBPATH="''${3:-.}"

    mkdir -p "$TARGET"
    cd "$TARGET"
    ${pkgs.borgbackup}/bin/borg extract "${repoPath}::$ARCHIVE" "$SUBPATH"
    echo "Restored to $TARGET"
  '';

  # Script to manually trigger backup
  mkManualBackupScript = { jobName }: pkgs.writeShellScriptBin "borg-backup-now" ''
    echo "Starting Borg backup..."
    sudo systemctl start borgbackup-job-${jobName}.service
    echo "Check status with: systemctl status borgbackup-job-${jobName}.service"
  '';
}
