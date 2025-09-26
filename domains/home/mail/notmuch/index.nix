{ config, lib, pkgs, ... }:

let
  cfg      = config.hwc.home.mail.notmuch or {};
  accAttrs = config.hwc.home.mail.accounts or {};
  accs     = lib.attrValues accAttrs;

  # ---------- simple helpers (local only) ----------
  maildirRoot =
    let v = cfg.maildirRoot or "";
    in if v != "" then v else "${config.home.homeDirectory}/Maildir";

  userName     = let v = cfg.userName or "";     in (if v != "" then v else "eric okeefe");
  primaryEmail = let v = cfg.primaryEmail or ""; in (if v != "" then v else "eriqueo@proton.me");
  otherEmails  = let v = cfg.otherEmails or [];  in (if v != [] then v else
                    [ "eric@iheartwoodcraft.com" "eriqueokeefe@gmail.com" "heartwoodcraftmt@gmail.com" ]);
  newTags      = cfg.newTags or [ "unread" "inbox" ];

  mkSemi = xs: lib.concatStringsSep ";" xs;
  orJoin = xs: lib.concatStringsSep " OR " xs;
  isGmail = a: (a.type or "") == "gmail";
  mdName  = a: (a.maildirName or a.name or "");

  # Gmail exposes two historical namespaces; handle both explicitly.
  mkGmail = md: sub: [
    ''folder:"${md}/[Gmail]/${sub}"''
    ''folder:"${md}/[Google Mail]/${sub}"''
  ];

  # ---------- special-folder clauses (explicit, per account) ----------
  sentClauses =
    lib.flatten (map (a: let md = mdName a;
      in if isGmail a then mkGmail md "Sent Mail" else [ ''folder:"${md}/Sent"'' ]) accs);

  draftsClauses =
    lib.flatten (map (a: let md = mdName a;
      in if isGmail a then mkGmail md "Drafts" else [ ''folder:"${md}/Drafts"'' ]) accs);

  trashClauses =
    lib.flatten (map (a: let md = mdName a;
      in if isGmail a then mkGmail md "Trash" else [ ''folder:"${md}/Trash"'' ]) accs);

  spamClauses =
    lib.flatten (map (a: let md = mdName a;
      in if isGmail a then mkGmail md "Spam" else [ ''folder:"${md}/Spam"'' ]) accs);

  archiveClauses =
    lib.flatten (map (a: let md = mdName a;
      in if isGmail a then mkGmail md "All Mail" else [ ''folder:"${md}/Archive"'' ''folder:"${md}/All Mail"'' ]) accs);

  # ---------- rule block (newsletter/notification/finance/action) ----------
  R = cfg.rules or {};
  mkFrom = s: "from:" + s;
  mkSubj = s: "subject:" + lib.toLower s;

  newsletterQ   = orJoin (["list:\"*\""] ++ map mkFrom (R.newsletterSenders   or []));
  notificationQ = orJoin (map mkFrom (R.notificationSenders or []));
  financeQ      = orJoin (map mkFrom (R.financeSenders      or []));
  actionQ       = orJoin (map mkSubj (R.actionSubjects      or []));

  ruleLine = tag: ops: q:
    if q == "" then "" else ''notmuch tag ${tag} ${ops} -- '${q}'\n'';

  rulesBlock = ''
    # Classification rules
    ${ruleLine "+newsletter"  "-inbox" newsletterQ}
    ${ruleLine "+notification" "-inbox" notificationQ}
    ${ruleLine "+finance"     "-inbox" financeQ}
    ${ruleLine "+action"      ""       actionQ}
    # Safety
    notmuch tag -action -newsletter -notification -- 'tag:sent OR tag:trash OR tag:spam OR tag:draft'
  '';

  # ---------- post-new hook (only emit lines when we have clauses) ----------
  postNewHookText =
    ''
      #!/usr/bin/env bash
      set -euo pipefail
    ''
    + lib.optionalString (sentClauses    != []) ''notmuch tag +sent   -inbox -unread -- '${orJoin sentClauses}'\n''
    + lib.optionalString (draftsClauses  != []) ''notmuch tag +draft  -inbox -unread -- '${orJoin draftsClauses}'\n''
    + lib.optionalString (trashClauses   != []) ''notmuch tag +trash  -inbox -unread -- '${orJoin trashClauses}'\n''
    + lib.optionalString (spamClauses    != []) ''notmuch tag +spam   -inbox -unread -- '${orJoin spamClauses}'\n''
    + lib.optionalString (archiveClauses != []) ''notmuch tag +archive        -inbox   -- '${orJoin archiveClauses}'\n''
    + "\n${rulesBlock}";

  # ---------- saved searches ----------
  defaultSearches = {
    inbox         = "tag:inbox AND tag:unread";
    action        = "tag:action AND tag:unread";
    finance       = "tag:finance AND tag:unread";
    newsletter    = "tag:newsletter AND tag:unread";
    notifications = "tag:notification AND tag:unread";
    sent          = "tag:sent";
    archive       = "tag:archive";
  };
  allSearches = defaultSearches // (cfg.savedSearches or {});
  savedSearchesText =
    lib.concatStringsSep "\n" (lib.mapAttrsToList (n: q: "${n}=${q}") allSearches) + "\n";

  # Optional tiny dashboard (kept here for simplicity; guarded by option)
  dashboardScript = ''
    #!/usr/bin/env bash
    set -euo pipefail
    printf "inbox (unread): %s\n" "$(notmuch count 'tag:inbox and tag:unread')"
    printf "sent:           %s\n" "$(notmuch count 'tag:sent')"
    printf "archive:        %s\n" "$(notmuch count 'tag:archive')"
    printf "drafts:         %s\n" "$(notmuch count 'tag:draft')"
    printf "spam:           %s\n" "$(notmuch count 'tag:spam')"
    printf "trash:          %s\n" "$(notmuch count 'tag:trash')"
  '';
in
{
  # aggregator: minimal, single module
  imports = [ ./options.nix ];

  config = {
    home.packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];

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

    # Real hook (declarative); notmuch will execute this path
    home.file."${maildirRoot}/.notmuch/hooks/post-new" = {
      text = postNewHookText;
      executable = true;
    };

    # Saved searches
    xdg.configFile."notmuch/saved-searches".text = savedSearchesText;

    # Optional dashboard
    home.file.".local/bin/mail-dashboard" = lib.mkIf (cfg.installDashboard or false) {
      text = dashboardScript;
      executable = true;
    };
  };
}
