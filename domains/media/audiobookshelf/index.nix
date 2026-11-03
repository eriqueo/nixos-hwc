# domains/media/audiobookshelf/index.nix
{ lib, config, pkgs, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.audiobookshelf;
  paths = config.hwc.paths;
  # Temporary supported runtime for the pinned app. Retire when an upstream
  # image passes actual runtime/native/trust and current-data recovery checks.
  runtime = helpers.mkNodeRuntimeImage {
    name = "audiobookshelf";
    appVersion = "2.37.2";
    nodeVersion = "24.22.2";
    upstreamImage = "ghcr.io/advplyr/audiobookshelf@sha256:37c2057e150694970442579815c646fe6bdc01c95b9d1547c4c9068be8844ef3";
    nodeSourceImage = "docker.io/library/node@sha256:4eefa1bfce4197942661ef9148247d779ddf1bb0ee006d3294a467609de60724";
  };
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

    dataDir = mkOption {
      type = types.str;
      default = "${paths.apps.root}/audiobookshelf/config";
      description = "Application configuration and SQLite database directory";
    };

    image = mkOption {
      type = types.str;
      default = runtime.image;  # critical tier: immutable app/runtime inputs
      description = "Qualified same-app image built from system.build.audiobookshelfRuntimeImageRecipe";
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
      default = toString paths.media.audiobooks;
      description = "Path to audiobooks library";
    };

    podcasts = mkOption {
      type = types.path;
      default = toString paths.media.podcasts;
      description = "Path to podcasts library";
    };

    metadata = mkOption {
      type = types.path;
      default = "${paths.media.books}/.audiobookshelf-metadata";
      description = "Path to store metadata (cover images, descriptions, etc.)";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.audiobookshelfRuntimeImageRecipe = runtime.dockerfile;
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = helpers.mkVpnAssertions {
      name = "audiobookshelf";
      networkMode = cfg.network.mode;
      gluetunInstances = config.hwc.networking.gluetun.instances;
    } ++ [
      {
        assertion = config.hwc.paths.media.root != null;
        message = "audiobookshelf container requires hwc.paths.media.root to be defined";
      }
    ];
  };
}
