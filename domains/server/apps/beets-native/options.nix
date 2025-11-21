{ lib, ... }:

{
  options.hwc.server.apps.beets-native = {
    enable = lib.mkEnableOption "beets music organizer (native installation)";

    musicDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/media/music";
      description = "Music library directory";
    };

    importDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/hot/downloads/music";
      description = "Import staging directory";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/beets";
      description = "Beets config and database directory";
    };
  };
}
