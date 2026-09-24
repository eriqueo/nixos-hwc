# domains/media/frigate/parts/cleanup.nix
#
# Automated surveillance recording cleanup
# Gated behind hwc.media.frigate.cleanup.enable
#
# Prunes only empty directories. Frigate owns file retention and database rows.

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
      description = "Prune empty Frigate recording directories";
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
      };
      path = [ pkgs.findutils pkgs.coreutils ];
      script = ''
        # AUTO-MANAGED footage: Frigate alone deletes files according to the
        # native retention in parts/config.nix. Never delete files behind its DB.

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
