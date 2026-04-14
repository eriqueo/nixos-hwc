{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.hwc.media.beets;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  options.hwc.media.beets = {
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
      default = "${config.hwc.paths.apps.root}/beets/config";
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

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable { };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
