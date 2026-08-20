{ lib, config, ... }:
let
  cfg = config.hwc.business.paperless;
  paths = config.hwc.paths;
  appsRoot = paths.apps.root;
  paperlessRoot = if appsRoot != null then "${appsRoot}/paperless" else null;
  envDir = "/run/paperless-env";
in
{
  config = lib.mkIf cfg.enable {
    # Storage retention policy:
    # - CRITICAL (indefinite + backup): originals/archive/thumbnails under storage.mediaDir
    # - AUTO-MANAGED: staging/export cleanup via systemd timer (see parts/config.nix)
    #
    # SOLE producer of these paths. consume/export/media are podman bind-mount
    # sources: if one is missing at container start podman fails with
    # `statfs <dir>: no such file or directory` (2026-07-06 crash loop, 1600+
    # restarts). A duplicate producer in parts/config.nix asked for 0775 and was
    # silently ignored as a duplicate line; 0750 below is what has always been
    # in effect and what paperless (uid 1000) actually runs on. Don't re-add a
    # second producer — add the path here.
    #
    # tmpfiles runs at boot/activation only, so it cannot defend against a
    # nightly deleter; that is fixed at the deleter (`-mindepth 1`), not here.
    systemd.tmpfiles.rules = lib.flatten [
      (lib.optional (appsRoot != null) "d ${appsRoot} 0755 root root -")
      (lib.optional (paperlessRoot != null) "d ${paperlessRoot} 0750 eric users -")
      (lib.optional (cfg.storage.dataDir != null) "d ${cfg.storage.dataDir} 0750 eric users -")

      (lib.optional (cfg.storage.mediaDir != null) "d ${cfg.storage.mediaDir} 0750 eric users -")
      (lib.optional (cfg.storage.mediaDir != null) "d ${cfg.storage.mediaDir}/originals 0750 eric users -")
      (lib.optional (cfg.storage.mediaDir != null) "d ${cfg.storage.mediaDir}/archive 0750 eric users -")
      (lib.optional (cfg.storage.mediaDir != null) "d ${cfg.storage.mediaDir}/thumbnails 0750 eric users -")

      (lib.optional (cfg.storage.consumeDir != null) "d ${cfg.storage.consumeDir} 0750 eric users -")
      (lib.optional (cfg.storage.exportDir != null) "d ${cfg.storage.exportDir} 0750 eric users -")
      (lib.optional (cfg.storage.stagingDir != null) "d ${cfg.storage.stagingDir} 0750 eric users -")

      "d ${envDir} 0750 root secrets -"
    ];
  };
}
