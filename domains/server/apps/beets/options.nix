{ lib, ... }:

let
  inherit (lib) types mkOption;
in
{
  options.hwc.server.apps.beets = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the Beets music organizer container.";
    };

    image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/beets:latest";
      description = "The Docker image for Beets.";
    };

    musicDir = mkOption {
      type = types.str;
      default = "/mnt/media/music";
      description = "The directory where your music is stored.";
    };

    configDir = mkOption {
      type = types.str;
      default = "/var/lib/beets";
      description = "The directory to store Beets configuration.";
    };
  };
}
