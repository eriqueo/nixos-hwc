# domains/media/frigate/parts/cleanup.nix
#
# Automated surveillance recording cleanup
# Gated behind hwc.media.frigate.cleanup.enable
#
# Enforces retention policy as a backup to Frigate's native cleanup.

{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.frigate;
  cleanupCfg = cfg.cleanup;
  # Recordings/clips are standard Frigate subdirectories under mediaPath
  basePath = lib.removeSuffix "/media" cfg.storage.mediaPath;
in
{
  config = lib.mkIf (cfg.enable && cleanupCfg.enable) {
    systemd.timers.frigate-cleanup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cleanupCfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.frigate-cleanup = {
      description = "Cleanup old Frigate surveillance recordings";
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      path = [ pkgs.findutils pkgs.coreutils ];
      script = ''
        # Frigate handles its own cleanup, but this provides backup enforcement
        # Delete recordings older than ${toString cleanupCfg.recordingRetentionDays} days
        find ${basePath}/recordings -type f -name "*.mp4" -mtime +${toString cleanupCfg.recordingRetentionDays} -delete 2>/dev/null || true

        # Delete clips older than ${toString cleanupCfg.clipRetentionDays} days
        find ${basePath}/clips -type f -name "*.mp4" -mtime +${toString cleanupCfg.clipRetentionDays} -delete 2>/dev/null || true

        # Delete empty directories
        find ${basePath} -type d -empty -delete 2>/dev/null || true

        # Log cleanup stats
        RECORDINGS_SIZE=$(du -sh ${basePath}/recordings 2>/dev/null | cut -f1)
        CLIPS_SIZE=$(du -sh ${basePath}/clips 2>/dev/null | cut -f1)
        echo "Frigate cleanup complete - Recordings: $RECORDINGS_SIZE, Clips: $CLIPS_SIZE"
      '';
    };
  };
}
