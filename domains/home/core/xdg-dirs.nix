# domains/home/core/xdg-dirs.nix
# Declarative XDG user directories (Home Manager) aligned with HWC paths
# System defaults are set in domains/system/core/paths.nix; this keeps ~/.config/user-dirs.dirs in sync

{ config, lib, ... }:

let
  home = config.home.homeDirectory;
  inbox = "${home}/000_inbox";
  work = "${home}/100_hwc";
  media = "${home}/500_media";
in {
  config = {
    xdg.userDirs = {
      enable = true;
      createDirectories = true;

      # Declarative XDG mapping aligned to the Dewey/underscore scheme
      desktop = inbox;
      download = "${inbox}/downloads";
      documents = "${work}/110_documents";
      templates = "${work}/130_reference/templates";
      publicShare = inbox;
      pictures = "${media}/510_pictures";
      music = "${media}/520_music";
      videos = "${media}/530_videos";
    };
  };
}
