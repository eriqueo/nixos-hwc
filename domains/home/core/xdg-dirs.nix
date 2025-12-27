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

    # Ensure HWC domain folders exist (Dewey/underscore scheme)
    home.activation.ensureHwcDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p \
        ${home}/000_inbox ${home}/000_inbox/downloads \
        ${home}/100_hwc/100_inbox ${home}/100_hwc/110_documents ${home}/100_hwc/120_projects ${home}/100_hwc/130_reference ${home}/100_hwc/140_assets ${home}/100_hwc/190_archive \
        ${home}/200_personal/200_inbox ${home}/200_personal/210_documents ${home}/200_personal/220_projects ${home}/200_personal/230_reference ${home}/200_personal/240_assets ${home}/200_personal/290_archive \
        ${home}/300_tech/300_inbox ${home}/300_tech/310_documents ${home}/300_tech/320_projects ${home}/300_tech/330_reference ${home}/300_tech/340_assets ${home}/300_tech/390_archive \
        ${home}/400_mail ${home}/500_media/510_pictures ${home}/500_media/520_music ${home}/500_media/530_videos
    '';
  };
}
