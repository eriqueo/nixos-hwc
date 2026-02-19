{ lib, config, ... }:
let
  cfg = config.hwc.server.containers.paperless;
  paths = config.hwc.paths;
  appsRoot = paths.apps.root;
  paperlessRoot = if appsRoot != null then "${appsRoot}/paperless" else null;
  envDir = "/run/paperless";
in
{
  config = lib.mkIf cfg.enable {
    # Storage retention policy:
    # - CRITICAL (indefinite + backup): originals/archive/thumbnails under storage.mediaDir
    # - AUTO-MANAGED: staging/export cleanup via systemd timer (see parts/config.nix)
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
