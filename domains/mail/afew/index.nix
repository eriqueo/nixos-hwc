{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg   = config.hwc.mail.afew or {};
  nmCfg = config.hwc.mail.notmuch or {};
  transport = config.hwc.mail.classifier.contract.mailboxTransport;
  intent = target: "tag:${transport.intentTagPrefix}${target}";

  afewPkg = import ./package.nix { inherit lib pkgs; cfg = cfg; };

  mailRoot =
    let base = nmCfg.maildirRoot or "";
    in if base != "" then base else "${config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail"}/Maildir";

  # Folder-state filters: tag messages that arrive already in Archive/Trash/Spam
  # (e.g. synced from Proton where they were already there)
  # Content classification deliberately does not happen here; Laya is the sole
  # automatic producer of State, Domain, and factual traits.
  folderStateFilters = ''
[Filter.1]
query = folder:proton/Archive AND NOT tag:archive
tags = +archive
message = Tag messages already in Proton Archive

[Filter.2]
query = folder:proton/Trash AND NOT tag:trash
tags = +trash
message = Tag messages already in Proton Trash

[Filter.3]
query = folder:proton/Spam AND NOT tag:spam
tags = +spam
message = Tag messages already in Proton Spam
'';

  # Only durable shared-command intents authorize a move. Folder tags describe
  # fetched residency and must never resurrect a phone Trash/Archive action.
  mailMoverSection = ''
[MailMover]
folders = proton/inbox proton/Archive proton/Trash proton/Spam
rename = True
max_age = 30

proton/inbox = '${intent "archive"}':proton/Archive '${intent "trash"}':proton/Trash
proton/Archive = '${intent "inbox"}':proton/inbox '${intent "trash"}':proton/Trash
proton/Trash = '${intent "inbox"}':proton/inbox '${intent "archive"}':proton/Archive
proton/Spam = '${intent "inbox"}':proton/inbox '${intent "archive"}':proton/Archive '${intent "trash"}':proton/Trash
'';

  conf = ''
[global]
# notmuch config discovery is done via NOTMUCH_CONFIG; no database path needed here
maildir = ${mailRoot}

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
