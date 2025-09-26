{ lib, pkgs, maildirRoot, userName, primaryEmail, otherEmails, newTags, excludeFolders ? [] }:
let
  mkSemi = xs: lib.concatStringsSep ";" xs;
in {
  packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];

  programs.notmuch = {
    enable = true;
    new.tags = newTags;
    extraConfig = lib.mkMerge [
      {
        database.path = maildirRoot;
        user = {
          name = userName;
          primary_email = primaryEmail;
          other_email = mkSemi otherEmails;
        };
        maildir.synchronize_flags = "true";
      }
      (lib.optionalAttrs (excludeFolders != []) {
        new.ignore = mkSemi excludeFolders;
      })
    ];
  };
}
