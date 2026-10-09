{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg   = config.hwc.mail.afew or {};
  nmCfg = config.hwc.mail.notmuch or {};
  transport = config.hwc.mail.classifier.contract.mailboxTransport;
  folders = transport.localMailboxes;

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
query = folder:${folders.archive} AND NOT tag:archive
tags = +archive
message = Tag messages already in Proton Archive

[Filter.2]
query = folder:${folders.trash} AND NOT tag:trash
tags = +trash
message = Tag messages already in Proton Trash

[Filter.3]
query = folder:${folders.spam} AND NOT tag:spam
tags = +spam
message = Tag messages already in Proton Spam
'';

  conf = ''
[global]
# notmuch config discovery is done via NOTMUCH_CONFIG; no database path needed here
maildir = ${mailRoot}

${folderStateFilters}
''; # trailing newline expected by afew
in
{
  config = lib.mkIf (cfg.enable or false) {
    home.packages = [ afewPkg ];

    xdg.configFile."afew/config".text = conf;
  };
}
