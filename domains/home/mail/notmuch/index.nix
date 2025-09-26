{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.notmuch;
  mkSemicolonList = xs: lib.concatStringsSep ";" xs;
  mkSavedSearchFile = builtins.concatStringsSep "\n" (lib.mapAttrsToList (n: q: "${n}=${q}") cfg.savedSearches);
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];

    programs.notmuch = {
      enable = true;
      new.tags = cfg.newTags;
      extraConfig = {
        database.path = cfg.maildirRoot;
        user = {
          name = cfg.userName;
          primary_email = cfg.primaryEmail;
          other_email = mkSemicolonList cfg.otherEmails;
        };
        maildir.synchronize_flags = "true";
      } // lib.optionalAttrs (cfg.excludeFolders != []) {
        index.exclude = mkSemicolonList cfg.excludeFolders;
      };
      hooks.postNew = cfg.postNewHook;
    };

    xdg.configFile."notmuch/saved-searches".text = mkSavedSearchFile;

    home.file.".local/bin/mail-dashboard".source = lib.mkIf cfg.installDashboard ./parts/dashboard.sh;
    home.file.".local/bin/mail-dashboard".executable = lib.mkIf cfg.installDashboard true;

    home.file.".local/bin/mail-sample".source = lib.mkIf cfg.installSampler ./parts/sample.sh;
    home.file.".local/bin/mail-sample".executable = lib.mkIf cfg.installSampler true;
  };
}
