# domains/server/native/orchestration/audiobook-copier/options.nix
#
# Audiobook Copier - Copies audiobooks from qBittorrent downloads to Audiobookshelf library
# Preserves source files for continued seeding

{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.native.orchestration.audiobookCopier = {
    enable = mkEnableOption "Audiobook copier service";

    sourceDir = mkOption {
      type = types.path;
      default = "/mnt/hot/downloads/books";
      description = "Source directory for downloaded audiobooks (qBittorrent books category)";
    };

    destDir = mkOption {
      type = types.path;
      default = "/mnt/media/books/audiobooks";
      description = "Destination directory for Audiobookshelf library";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/hwc/audiobook-copier";
      description = "State directory for tracking processed audiobooks";
    };

    triggerLibraryScan = mkOption {
      type = types.bool;
      default = true;
      description = "Trigger Audiobookshelf library scan after copying";
    };

    audiobookshelfUrl = mkOption {
      type = types.str;
      default = "http://localhost:13378";
      description = "Audiobookshelf API URL";
    };

    audioExtensions = mkOption {
      type = types.listOf types.str;
      default = [ "mp3" "m4a" "m4b" "flac" "opus" "ogg" "wav" "aac" ];
      description = "Audio file extensions to detect audiobooks";
    };
  };
}
