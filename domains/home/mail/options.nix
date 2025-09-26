{ lib, ... }:
let t = lib.types; in
{
  options.hwc.home.mail = {
    # One switch for the whole mail stack; default on if you want it everywhere
    enable = lib.mkEnableOption "Mail domain" // { default = true; };

    # Shared data schema (no separate toggle needed)
    accounts = lib.mkOption {
      type = t.attrsOf (t.submodule ({ name, ... }: {
        options = {
          name = lib.mkOption { type = t.str; default = name; };
          realName = lib.mkOption { type = t.str; default = ""; };
          address = lib.mkOption { type = t.str; };

          type = lib.mkOption { type = t.enum [ "proton-bridge" "gmail" ]; default = "proton-bridge"; };
          login = lib.mkOption { type = t.str; default = ""; };
          bridgeUsername = lib.mkOption { type = t.str; default = ""; };

          password.mode    = lib.mkOption { type = t.enum [ "pass" "agenix" "command" ]; default = "pass"; };
          password.pass    = lib.mkOption { type = t.str; default = ""; };
          password.agenix  = lib.mkOption { type = t.str; default = ""; };
          password.command = lib.mkOption { type = t.str; default = ""; };

          maildirName = lib.mkOption { type = t.str; default = name; };

          imapHost = lib.mkOption { type = t.nullOr t.str; default = null; };
          imapPort = lib.mkOption { type = t.nullOr t.int; default = null; };
          imapTls  = lib.mkOption { type = t.nullOr (t.enum [ "None" "STARTTLS" "IMAPS" ]); default = null; };
          extraMbsync = lib.mkOption { type = t.lines; default = ""; };

          smtpHost = lib.mkOption { type = t.nullOr t.str; default = null; };
          smtpPort = lib.mkOption { type = t.nullOr t.int; default = null; };
          startTLS = lib.mkOption { type = t.nullOr t.bool; default = null; };
          extraMsmtp = lib.mkOption { type = t.lines; default = ""; };

          sync.patterns = lib.mkOption { type = t.listOf t.str; default = [ "INBOX" "Sent" "Drafts" "Trash" ]; };
          send.msmtpAccount = lib.mkOption { type = t.str; default = name; };
          primary = lib.mkOption { type = t.bool; default = false; };
        };
      }));
      default = {};
      description = "Shared mail accounts for all mail components.";
    };

    # (Optional) per-program toggles; default true for your “everything on” stance
    mbsync.enable  = lib.mkEnableOption "mbsync"  // { default = true; };
    msmtp.enable   = lib.mkEnableOption "msmtp"   // { default = true; };
    notmuch.enable = lib.mkEnableOption "notmuch" // { default = true; };
    bridge.enable  = lib.mkEnableOption "Proton Bridge" // { default = true; };
    abook.enable   = lib.mkEnableOption "abook"   // { default = true; };
  };
}
