# modules/home/core/mail/options.nix
{ lib, config, ... }:

{
  # Back-compat: keep the old path working while everything migrates
  imports = [
    (lib.mkAliasOptionModule
      [ "features" "neomutt" "accounts" ]
      [ "hwc" "home" "core" "mail" "accounts" ])
    (lib.mkAliasOptionModule
      [ "features" "mail" ]
      [ "hwc" "home" "core" "mail" ])
  ];

  options.hwc.home.core.mail = {
    enable = lib.mkEnableOption "Core mail plumbing (mbsync/msmtp/abook/notmuch).";

    # Canonical, client-agnostic accounts (shared by all mail apps)
    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          # -------- Identity --------
          name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Internal account key (also default Maildir name).";
          };
          realName = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Full name for outgoing mail (Realname).";
          };
          address = lib.mkOption {
            type = lib.types.str;
            example = "eric@iheartwoodcraft.com";
            description = "Email address for From:.";
          };

          # -------- Backend/provider --------
          type = lib.mkOption {
            type = lib.types.enum [ "proton-bridge" "gmail" ];
            default = "proton-bridge";
            description = "Provider backend (affects default hosts/ports/auth).";
          };

          # -------- Login (optional; falls back when empty) --------
          login = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "IMAP/SMTP login. Empty ⇒ fall back to address/bridgeUsername.";
          };
          bridgeUsername = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Legacy Proton Bridge local username (deprecated; prefer 'login').";
          };

          # -------- Password source --------
          password = {
            mode = lib.mkOption {
              type = lib.types.enum [ "pass" "agenix" "command" ];
              default = "pass";
              description = "Where to fetch the password.";
            };
            pass = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "pass entry, e.g. 'email/proton/bridge'.";
            };
            agenix = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Path to a decrypted secret file (e.g. /run/agenix/...).";
            };
            command = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Shell command that prints the password to stdout.";
            };
          };

          # -------- Maildir naming --------
          maildirName = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Top-level Maildir under ~/Maildir (e.g. 'proton', 'gmail-personal').";
          };

          # -------- IMAP (mbsync) overrides (all optional) --------
          imapHost = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null; # default inferred from 'type'
            description = "Override IMAP host (null ⇒ infer from provider).";
          };
          imapPort = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null; # default inferred from 'type'
            description = "Override IMAP port (null ⇒ infer from provider).";
          };
          imapTls = lib.mkOption {
            type = lib.types.nullOr (lib.types.enum [ "None" "STARTTLS" "IMAPS" ]);
            default = null; # default inferred from 'type'
            description = "Override IMAP TLSType for mbsync (None/STARTTLS/IMAPS).";
          };
          extraMbsync = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra lines appended to this account's mbsync block (escape hatch).";
          };

          # -------- SMTP (msmtp) overrides (all optional) --------
          smtpHost = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null; # default inferred from 'type'
            description = "Override SMTP host (null ⇒ infer from provider).";
          };
          smtpPort = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null; # default inferred from 'type'
            description = "Override SMTP port (null ⇒ infer from provider).";
          };
          startTLS = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null; # default inferred from 'type'
            description = "Override STARTTLS (true/false); null ⇒ infer from provider.";
          };
          extraMsmtp = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Extra lines appended to this account's msmtp block (escape hatch).";
          };

          # -------- Sync selection --------
          sync = {
            patterns = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "INBOX" "Sent" "Drafts" "Trash" ];
              description = "mbsync channel patterns to sync.";
            };
          };

          # -------- Sending config --------
          send = {
            msmtpAccount = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "msmtp 'account' label used for this identity.";
            };
          };

          # -------- Default sender --------
          primary = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this account is the default sender (msmtp 'account default').";
          };
        };
      }));
      default = {};
      description = "Declarative mail accounts (shared by msmtp/mbsync/neomutt/etc.).";
    };
  };
}
