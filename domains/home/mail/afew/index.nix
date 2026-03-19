{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg   = config.hwc.home.mail.afew or {};
  nmCfg = config.hwc.home.mail.notmuch or {};

  afewPkg = import ./package.nix { inherit lib pkgs; cfg = cfg; };

  mailRoot =
    let base = nmCfg.maildirRoot or "";
    in if base != "" then base else "${config.hwc.paths.user.mail or "/home/eric/400_mail"}/Maildir";

  rules = nmCfg.rules or {};

  joinFrom = lst:
    if lst == [] then ""
    else lib.concatStringsSep " OR " (map (s: "from:${s}") lst);

  newsletterClause   = joinFrom (rules.newsletterSenders or []);
  notificationClause = joinFrom (rules.notificationSenders or []);
  financeClause      = joinFrom (rules.financeSenders or []);
  actionClause       = joinFrom (rules.actionSubjects or []);

  # Afew 3.0+ uses numbered filter sections: [Filter.1], [Filter.2], etc.
  filterList = lib.filter (f: f.clause != "") [
    { num = 1; clause = newsletterClause; tag = "newsletter"; msg = "Tag newsletters"; }
    { num = 2; clause = notificationClause; tag = "notification"; msg = "Tag notifications"; }
    { num = 3; clause = financeClause; tag = "finance"; msg = "Tag finance emails"; }
    { num = 4; clause = actionClause; tag = "action"; msg = "Tag actionable emails"; }
  ];

  makeFilter = f: ''
[Filter.${toString f.num}]
query = ${f.clause}
tags = +${f.tag}
message = ${f.msg}
'';

  filters = lib.concatStringsSep "\n" (map makeFilter filterList);

  # Folder-state filters: tag messages that arrive already in Archive/Trash/Spam
  # (e.g. synced from Proton where they were already there)
  folderStateFilters =
    let base = lib.length filterList + 1; in ''
[Filter.${toString base}]
query = folder:proton/Archive AND NOT tag:archive
tags = +archive
message = Tag messages already in Proton Archive

[Filter.${toString (base + 1)}]
query = folder:proton/Trash AND NOT tag:trash
tags = +trash
message = Tag messages already in Proton Trash

[Filter.${toString (base + 2)}]
query = folder:proton/Spam AND NOT tag:spam
tags = +spam
message = Tag messages already in Proton Spam
'';

  # MailMover: physically moves Maildir files before mbsync, so mbsync
  # pushes the moves to Proton. Uses exact folder names from ls ~/400_mail/Maildir/proton/
  mailMoverSection = ''
[MailMover]
folders = proton/inbox proton/Archive proton/Trash proton/Spam
rename = True
max_age = 30

proton/inbox = 'tag:archive':proton/Archive 'tag:trash':proton/Trash 'tag:spam':proton/Spam 'NOT tag:inbox':proton/Archive
proton/Archive = 'tag:trash':proton/Trash
proton/Trash = 'tag:inbox':proton/inbox
proton/Spam = 'tag:inbox':proton/inbox
'';

  conf = ''
[global]
# notmuch config discovery is done via NOTMUCH_CONFIG; no database path needed here
maildir = ${mailRoot}

${filters}
${folderStateFilters}
${mailMoverSection}
''; # trailing newline expected by afew
in
{
  config = lib.mkIf (cfg.enable or false) {
    home.packages = [ afewPkg ];

    xdg.configFile."afew/config".text = conf;
  };
}
