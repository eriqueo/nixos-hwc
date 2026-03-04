# domains/server/containers/audiobookshelf/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.audiobookshelf = {
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
}
