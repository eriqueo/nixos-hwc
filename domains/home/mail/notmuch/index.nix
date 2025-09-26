{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.mail;
  on  = (cfg.enable or true) && (cfg.notmuch.enable or true);

  nm  = cfg.notmuch;  # your sub-options scope
  effectiveMaildirRoot =
    if (nm.maildirRoot or "") != "" then nm.maildirRoot
    else "${config.home.homeDirectory}/Maildir";

  vals = lib.attrValues (cfg.accounts or {});
  primary = let p = lib.filter (a: a.primary or false) vals;
            in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);
  primaryEmailAuto =
    if (nm.primaryEmail or "") != "" then nm.primaryEmail
    else (if primary != null then (primary.address or "") else "");
  mkSemis = lib.concatStringsSep ";";
  mkSaved = builtins.concatStringsSep "\n" (lib.mapAttrsToList (n: q: "${n}=${q}") nm.savedSearches);
in
{
  config = lib.mkIf on {
    home.packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];

    programs.notmuch = {
      enable = true;
      new.tags = nm.newTags;
      extraConfig = {
        database.path = effectiveMaildirRoot;
        user = { name = nm.userName; primary_email = primaryEmailAuto; other_email = mkSemis nm.otherEmails; };
        maildir.synchronize_flags = "true";
      } // lib.optionalAttrs (nm.excludeFolders != []) {
        index.exclude = mkSemis nm.excludeFolders;
      };
      hooks.postNew = nm.postNewHook;
    };

    xdg.configFile."notmuch/saved-searches".text = mkSaved;

    home.file.".local/bin/mail-dashboard".source = lib.mkIf nm.installDashboard ./parts/dashboard.sh;
    home.file.".local/bin/mail-dashboard".executable = lib.mkIf nm.installDashboard true;

    home.file.".local/bin/mail-sample".source = lib.mkIf nm.installSampler ./parts/sample.sh;
    home.file.".local/bin/mail-sample".executable = lib.mkIf nm.installSampler true;
  };
}
