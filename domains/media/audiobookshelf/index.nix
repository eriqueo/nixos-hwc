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
    appVersion = "2.32.1";
    nodeVersion = "24.22.1";
    upstreamImage = "ghcr.io/advplyr/audiobookshelf@sha256:f903aeade7ecf8beb2a5fd63411910705f7cff8d1acddb1a37a9171ef171b849";
    nodeSourceImage = "docker.io/library/node@sha256:47019ffab12a48f49795a8279603f87e91a64de017fb9aa874e64f489b686079";
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
