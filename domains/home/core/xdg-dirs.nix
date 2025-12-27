# domains/home/core/xdg-dirs.nix
# Declarative XDG user directories (Home Manager) aligned with HWC paths
# System defaults are set in domains/system/core/paths.nix; this keeps ~/.config/user-dirs.dirs in sync

{ config, lib, ... }:

let
  paths = config.hwc.paths;
  u     = paths.user;
  ud    = paths.userDirs;
in {
  config = {
    xdg.userDirs = {
      enable = true;
      createDirectories = true;

      # Use the centralized path definitions from domains/system/core/paths.nix
      desktop = ud.desktop;
      download = ud.download;
      documents = ud.documents;
      music = ud.music;
      pictures = ud.pictures;
      videos = ud.videos;
      publicShare = ud.publicShare;
      templates = ud.templates;
    };
  };
}
