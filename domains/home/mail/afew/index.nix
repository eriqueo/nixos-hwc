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

  filters = lib.concatStringsSep "\n" (lib.filter (s: s != "") [
    (if newsletterClause != "" then ''
[Filter "tag-newsletters"]
query = ${newsletterClause}
tags = +newsletter
'' else "")

    (if notificationClause != "" then ''
[Filter "tag-notifications"]
query = ${notificationClause}
tags = +notification
'' else "")

    (if financeClause != "" then ''
[Filter "tag-finance"]
query = ${financeClause}
tags = +finance
'' else "")

    (if actionClause != "" then ''
[Filter "tag-actionable"]
query = ${actionClause}
tags = +action
'' else "")
  ]);

  conf = ''
[global]
# notmuch config discovery is done via NOTMUCH_CONFIG; no database path needed here
maildir = ${mailRoot}

${filters}
''; # trailing newline expected by afew
in
{
  config = lib.mkIf (cfg.enable or false) {
    home.packages = [ afewPkg ];

    xdg.configFile."afew/config".text = conf;
  };
}
