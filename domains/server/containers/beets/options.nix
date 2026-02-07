# modules/server/containers/beets/options.nix
{ lib, config, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.beets = {
    enable = mkEnableOption "beets music organizer container";

    image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/beets:latest";
      description = "Container image for Beets";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "host" ];
      default = "media";
      description = "Network mode for the container";
    };

    configDir = mkOption {
      type = types.str;
      default = "${config.hwc.paths.hot.downloads}/beets";
      description = "Directory to store Beets configuration and database";
    };

    musicDir = mkOption {
      type = types.str;
      default = config.hwc.paths.media.music or "${config.hwc.paths.media.music}";
      description = "Directory where organized music will be stored";
    };

    importDir = mkOption {
      type = types.str;
      default = "${config.hwc.paths.hot.downloads}/music";
      description = "Directory for music imports";
    };
  };
}
