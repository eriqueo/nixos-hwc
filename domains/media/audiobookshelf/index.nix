# domains/media/audiobookshelf/index.nix
{ lib, config, pkgs, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.hwc.media.audiobookshelf;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  options.hwc.media.audiobookshelf = {
    enable = mkEnableOption "Audiobookshelf audiobook and podcast server";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/advplyr/audiobookshelf:latest";
      description = "Container image for Audiobookshelf";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode: media or vpn (through Gluetun)";
    };

    port = mkOption {
      type = types.int;
      default = 13378;
      description = "Port for Audiobookshelf web interface";
    };

    library = mkOption {
      type = types.path;
      default = "/mnt/media/books/audiobooks";
      description = "Path to audiobooks library";
    };

    podcasts = mkOption {
      type = types.path;
      default = "/mnt/media/podcasts";
      description = "Path to podcasts library";
    };

    metadata = mkOption {
      type = types.path;
      default = "/mnt/media/books/.audiobookshelf-metadata";
      description = "Path to store metadata (cover images, descriptions, etc.)";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = cfg.network.mode != "vpn" || config.hwc.networking.gluetun.enable;
        message = "audiobookshelf container with VPN mode requires gluetun to be enabled";
      }
      {
        assertion = config.hwc.paths.media.root != null;
        message = "audiobookshelf container requires hwc.paths.media.root to be defined";
      }
    ];
  };
}
