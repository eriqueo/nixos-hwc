{ lib, config, cfg, osConfig ? {}}:
let
  root = let v = cfg.maildirRoot or ""; in
    if v != "" then v else "${config.home.homeDirectory}/400_mail/Maildir";
in { maildirRoot = root; }