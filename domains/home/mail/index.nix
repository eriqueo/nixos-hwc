{ lib, osConfig ? {}, ... }:
let
  t = lib.types;
  dir = builtins.readDir ./.;

  # child program dirs that have an index.nix (mbsync, msmtp, notmuch, abook, bridge,…)
  kids = lib.filter (n:
    dir.${n} == "directory"
    && n != "accounts"
    && builtins.pathExists (./. + "/${n}/index.nix")
  ) (lib.attrNames dir);

  children = map (n: ./. + "/${n}/index.nix")
              (lib.sort (a: b: a < b) kids);

  haveAccounts = builtins.pathExists (./accounts/index.nix);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.mail = {
    enable = lib.mkEnableOption "Mail domain" // { default = true; };

    afew.enable = lib.mkEnableOption "Enable afew tagging and hook integration" // { default = true; };
    afew.package = lib.mkOption {
      type = t.nullOr t.package;
      default = null;
      description = "Optional override for the afew package (patched to drop pkg_resources; override is patched too).";
    };

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

          sync.enable = lib.mkOption { type = t.bool; default = true; description = "Whether to sync this account via mbsync"; };
          sync.patterns = lib.mkOption { type = t.listOf t.str; default = [ "INBOX" "Sent" "Drafts" "Trash" ]; };
          sync.wildcards = lib.mkOption { type = t.listOf t.str; default = []; description = "Additional wildcard patterns for mbsync (e.g., Folders/*)"; };
          mailboxMapping = lib.mkOption {
            type = t.attrsOf t.str;
            default = {};
            description = "Map remote IMAP folder names to local Maildir folder names. Format: { \"RemoteName\" = \"LocalName\"; }";
          };
          send.msmtpAccount = lib.mkOption { type = t.str; default = name; };
          primary = lib.mkOption { type = t.bool; default = false; };
        };
      }));
      default = {};
      description = "Shared mail accounts for all mail components.";
    };
  };

  imports =
    lib.optional haveAccounts (./accounts/index.nix)
    ++ children;

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};

}
