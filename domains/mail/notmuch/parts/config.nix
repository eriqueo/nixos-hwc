{ lib, pkgs, maildirRoot, userName, primaryEmail, otherEmails, newTags, excludeFolders ? [], osConfig ? {}}:
let
  mkSemi = xs: lib.concatStringsSep ";" xs;
in {
  packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];

  programs.notmuch = {
    enable = true;
    new.tags = newTags;
    # Only ignore folders explicitly passed in; default is none.
    new.ignore = excludeFolders;
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
