{ lib, config, ... }:

{
  options.hwc.server.beets-native = {
    enable = lib.mkEnableOption "beets music organizer (native installation)";

    musicDir = lib.mkOption {
      type = lib.types.str;
      default = config.hwc.paths.media.music or "/mnt/media/music";
      description = "Music library directory";
    };

    importDir = lib.mkOption {
      type = lib.types.str;
      default = config.hwc.paths.hot.downloads.music or "/mnt/hot/downloads/music";
      description = "Import staging directory";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/beets";
      description = "Beets config and database directory";
    };

    automation = {
      enable = lib.mkEnableOption "automated music import and cleanup" // { default = true; };

      importInterval = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "How often to auto-import new music";
      };

      dedupInterval = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "How often to run deduplication";
      };
    };
  };
}
