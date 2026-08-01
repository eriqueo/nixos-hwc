{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.readarr;
  appsRoot = config.hwc.paths.apps.root;
  configPath = "${appsRoot}/readarr/config";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (helpers.mkContainer {
      name = "readarr";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      gpuMode = "intel";
      timeZone = config.time.timeZone or "UTC";
      ports = [ "127.0.0.1:8787:8787" ];
      volumes = [
        "${configPath}:/config"
        # /books MUST denote the same host directory here as it does in the
        # calibre container, which mounts hwc.paths.media.books/ebooks at
        # /books. Readarr asks the calibre content server where it files
        # imports, gets back a path in *calibre's* namespace (/books/calibre),
        # and then resolves it in its own — so if the two disagree the check
        # fails and imports land nowhere. Mounting media.books here (one level
        # up) made /books mean two different things and broke every book import
        # from 2026-02-27 onward.
        "${config.hwc.paths.media.books}/ebooks:/books"
        # Audiobooks are not part of the calibre library, so they get their own
        # token rather than being smuggled in under /books.
        "${config.hwc.paths.media.audiobooks}:/audiobooks"
        "${config.hwc.paths.hot.root}/downloads:/downloads"
      ];
      environment = {
        READARR__URLBASE = "/readarr";
      };
      dependsOn = if cfg.network.mode == "vpn" then [ "gluetun" ] else [ "prowlarr" ];
    })
  ]);
}
