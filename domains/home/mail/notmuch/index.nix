{ config, lib, pkgs, ... }:
let
  cfgMail = config.hwc.home.mail;
  cfg     = cfgMail.notmuch;
  on      = (cfgMail.enable or true) && (cfgMail.notmuch.enable or true);


  # Render a list of “from contains X” OR-joined
    fromBlock = (xs: if xs == [] then "" else
      "notmuch tag +__TAG__ -inbox -- '" +
      (lib.concatStringsSep "' OR '" (map (s: "from:" + s) xs)) +
      "'\n");
  
    # Render subject contains; lowercased comparison is ok in notmuch
    subjBlock = (xs:
      if xs == [] then "" else
      "notmuch tag +action -- '" +
      (lib.concatStringsSep "' OR '" (map (s: "subject:" + s)) ) +
      "'\n");
  
    rulesScript =
      let
        newsletterCmd = lib.replaceStrings [ "__TAG__" ] [ "newsletter" ] (fromBlock cfg.rules.newsletterSenders);
        notificationCmd = lib.replaceStrings [ "__TAG__" ] [ "notification" ] (fromBlock cfg.rules.notificationSenders);
        financeCmd = lib.replaceStrings [ "__TAG__" ] [ "finance" ] (fromBlock cfg.rules.financeSenders);
        actionSubjCmd = subjBlock (map (x: lib.toLower x) cfg.rules.actionSubjects);
  
        raw = builtins.readFile ./parts/rules.sh;
        filled = lib.pipe raw [
            (s: lib.replaceStrings [ "__NEWSLETTER_BLOCK__"   ] [ newsletterCmd   ] s)
            (s: lib.replaceStrings [ "__NOTIFICATION_BLOCK__" ] [ notificationCmd ] s)
            (s: lib.replaceStrings [ "__FINANCE_BLOCK__"      ] [ financeCmd      ] s)
          ];
      in filled;
  # Derive maildir + primary email if unset
  effectiveMaildirRoot =
    if (cfg.maildirRoot or "") != "" then cfg.maildirRoot
    else "${config.home.homeDirectory}/Maildir";

  vals = lib.attrValues (cfgMail.accounts or {});
  primary =
    let p = lib.filter (a: a.primary or false) vals;
    in if p != [] then lib.head p else (if vals != [] then lib.head vals else null);
  primaryEmailAuto =
    if (cfg.primaryEmail or "") != "" then cfg.primaryEmail
    else (if primary != null then (primary.address or "") else "");

  mkSemis = lib.concatStringsSep ";";
  mkSaved = builtins.concatStringsSep "\n" (lib.mapAttrsToList (n: q: "${n}=${q}") cfg.savedSearches);
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf on {
    home.packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];

    programs.notmuch = {
      enable = true;
      new.tags = cfg.newTags;
      extraConfig = {
        database.path = effectiveMaildirRoot;
        user = {
          name = cfg.userName;
          primary_email = primaryEmailAuto;
          other_email    = mkSemis cfg.otherEmails;
        };
        maildir.synchronize_flags = "true";
      } // lib.optionalAttrs (cfg.excludeFolders != []) {
        index.exclude = mkSemis cfg.excludeFolders;
      };
      hooks.postNew = cfg.postNewHook;
    };

    xdg.configFile."notmuch/saved-searches".text = mkSaved;
    
    home.file.".local/bin/mail-dashboard" = lib.mkIf cfg.installDashboard {
        source = ./parts/dashboard.sh;
        executable = true;
     };
  
    home.file.".local/bin/mail-sample" = lib.mkIf cfg.installSampler {
      source = ./parts/sample.sh;
      executable = true;
    };
  };
}
