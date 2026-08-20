# domains/media/frigate/parts/cleanup.nix
#
# Automated surveillance recording cleanup
# Gated behind hwc.media.frigate.cleanup.enable
#
# Currently prunes only the empty date hierarchy under mediaPath. The mp4
# retention sweeps this file was written for are commented out and inert —
# see the note in the script for why turning them on is a policy decision.

{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.frigate;
  cleanupCfg = cfg.cleanup;
  # Recordings/clips are standard Frigate subdirectories under mediaPath.
  # basePath used to be `removeSuffix "/media" mediaPath`, i.e. the PARENT of
  # the real tree — so every `${basePath}/recordings` sweep below ran against a
  # path that does not exist (journal shows `Recordings: , Clips: ` — empty du,
  # nightly, for months). mediaPath is the actual root and the bind-mount source.
  mediaPath = cfg.storage.mediaPath;
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
        # The two mp4 retention sweeps are DISABLED, not merely broken. They ran
        # nightly for months against the wrong (non-existent) basePath, so they
        # have never deleted anything. Simply repointing them at mediaPath turns
        # a no-op into a first-ever deletion pass over ~506G / 60k files, with
        # thresholds (${toString cleanupCfg.recordingRetentionDays}d recordings /
        # ${toString cleanupCfg.clipRetentionDays}d clips) TIGHTER than Frigate's
        # own retention (parts/config.nix: recordings 3d, alerts/detections 14d —
        # and those 14d events pin the recording segments they reference). That
        # is not the "backup enforcement" this service claims to be: as written it
        # outranks Frigate and would break event playback.
        # Removal condition: set thresholds >= Frigate's native retention, then
        # uncomment against ${mediaPath} and delete this note.
        # find ${mediaPath}/recordings -type f -name "*.mp4" -mtime +${toString cleanupCfg.recordingRetentionDays} -delete 2>/dev/null || true
        # find ${mediaPath}/clips -type f -name "*.mp4" -mtime +${toString cleanupCfg.clipRetentionDays} -delete 2>/dev/null || true

        # Prune the empty date hierarchy Frigate's own cleanup leaves behind.
        # Scoped to recordings/ and clips/ with -mindepth 1 so it can never
        # reach ${mediaPath} itself — that is the container's bind-mount source
        # (index.nix:290), and deleting it makes the next start fail with
        # `statfs ...: no such file or directory`. The unscoped basePath form
        # here did exactly that; same shape burned paperless and media-cleanup.
        find ${mediaPath}/recordings ${mediaPath}/clips -mindepth 1 -type d -empty -delete 2>/dev/null || true

        # Log cleanup stats
        RECORDINGS_SIZE=$(du -sh ${mediaPath}/recordings 2>/dev/null | cut -f1)
        CLIPS_SIZE=$(du -sh ${mediaPath}/clips 2>/dev/null | cut -f1)
        echo "Frigate cleanup complete - Recordings: $RECORDINGS_SIZE, Clips: $CLIPS_SIZE"
      '';
    };
  };
}
