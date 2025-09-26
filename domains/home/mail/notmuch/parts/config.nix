# Pure helper: notmuch config & packages
{ lib, pkgs, maildirRoot, userName, primaryEmail, otherEmails, newTags }:

let mkSemi = xs: lib.concatStringsSep ";" xs;
in {
  packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];
  programs.notmuch = {
    enable = true;
    new.tags = newTags;
    extraConfig = {
      database.path = maildirRoot;
      user = {
        name = userName;
        primary_email = primaryEmail;
        other_email = mkSemi otherEmails;
      };
      maildir.synchronize_flags = "true";
    };
  };
}
