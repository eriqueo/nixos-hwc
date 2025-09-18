{ lib, ... }:

let
  t = lib.types;
in
{
  options.features.neomutt = {
    enable = lib.mkEnableOption "Enable NeoMutt (offline-first, HM-managed)";

    # Arbitrary materials injected from the system lane (e.g., agenix paths).
    materials = lib.mkOption {
      type = t.attrs;
      default = {};
      description = ''
        Resolved security materials for NeoMutt (e.g., agenix secret paths).
        Populated by modules/home/apps/neomutt/sys.nix; read this instead of system knobs directly.
      '';
    };

    # Per-account model (works for Proton Bridge, Gmail app-passwords, and generic IMAP)
    accounts = lib.mkOption {
      type = t.attrsOf (t.submodule ({ name, ... }: {
        options = {
          # Stable identifier used for Maildir and macro names (no spaces).
          name = lib.mkOption {
            type = t.str;
            default = name;
            description = "Stable account key (used in Maildir path by default).";
          };

          # What kind of backend it is; drives defaults.
          type = lib.mkOption {
            type = t.enum [ "proton-bridge" "gmail" "imap" ];
            description = "Provider type to derive sensible defaults.";
          };

          # Identity
          realName = lib.mkOption { type = t.str; description = "Full name (From:)."; };
          address  = lib.mkOption {
            type = t.str;
            description = "Email address used in From:. Also login for gmail/imap by default.";
          };

          # Login/username for IMAP/SMTP (Bridge LOCAL user for Proton; defaults to address otherwise).
          login = lib.mkOption {
            type = t.str;
            default = "";  # filled by config below
            description = "Login/username for IMAP/SMTP. Defaults to address for gmail/imap; REQUIRED for proton-bridge.";
          };

          # Local Maildir folder name under ~/Maildir (default = name).
          maildirName = lib.mkOption {
            type = t.str;
            default = "";  # filled by config below
            description = "Maildir root under ~/Maildir (e.g., 'proton', 'gmail-personal').";
          };

          # Make one account primary (used for default spoolfile).
          primary = lib.mkOption { type = t.bool; default = false; description = "If true, used as default spoolfile."; };

          # Password source (generic, works for Proton/Gmail)
          password = lib.mkOption {
            type = t.submodule {
              options = {
                mode = lib.mkOption {
                  type = t.enum [ "pass" "agenix" "command" ];
                  default = "pass";
                  description = "Where to read the secret from.";
                };
                pass = lib.mkOption {
                  type = t.nullOr t.str;
                  default = null;
                  description = "pass(1) entry path (e.g., 'email/proton/bridge' or 'email/gmail/personal').";
                };
                agenix = lib.mkOption {
                  type = t.nullOr t.path;
                  default = null;
                  description = "Path to agenix-managed secret file.";
                };
                command = lib.mkOption {
                  type = t.nullOr t.str;
                  default = null;
                  description = "Arbitrary shell command that prints the password to stdout.";
                };
              };
            };
            description = "Password provider for this account.";
          };

          # Sync preferences (mbsync)
          sync = lib.mkOption {
            type = t.submodule {
              options = {
                patterns = lib.mkOption {
                  type = t.listOf t.str;
                  default = [];  # filled by config below based on type
                  description = "IMAP folders to sync (IMAP-side names).";
                };
              };
            };
            default = {};
            description = "Synchronization settings.";
          };

          # Sending preferences (msmtp)
          send = lib.mkOption {
            type = t.submodule {
              options = {
                enable = lib.mkOption { type = t.bool; default = true; };
                msmtpAccount = lib.mkOption {
                  type = t.str;
                  default = "";  # filled by config below (defaults to name)
                  description = "Logical msmtp account name to emit/use.";
                };
              };
            };
            default = {};
            description = "Outbound mail (msmtp) preferences.";
          };

          # -------- Deprecated (kept for compatibility) --------
          bridgeUsername = lib.mkOption {
            type = t.str; default = "";
            description = "DEPRECATED: use 'login'. Proton Bridge LOCAL username.";
          };
          useAgenixPassword = lib.mkOption {
            type = t.bool; default = false;
            description = "DEPRECATED: use 'password.mode = agenix'.";
          };
          bridgePasswordCommand = lib.mkOption {
            type = t.nullOr t.str; default = null;
            description = "DEPRECATED: use 'password.command' or 'password.pass'.";
          };
        };

        # Derived defaults & normalization
        config = {
          # login default
          login = lib.mkDefault (
            lib.mkIf (builtins.elem config.type [ "gmail" "imap" ]) config.address
          );

          # If proton-bridge and no login was set, fall back to deprecated bridgeUsername (still better than empty).
          login = lib.mkDefault (
            lib.mkIf (config.type == "proton-bridge" && config.login == "" && config.bridgeUsername != "")
              config.bridgeUsername
          );

          # maildirName default = name
          maildirName = lib.mkDefault (if config.maildirName == "" then config.name else config.maildirName);

          # msmtp logical account name default = name
          send.msmtpAccount = lib.mkDefault (if config.send.msmtpAccount == "" then config.name else config.send.msmtpAccount);

          # sync patterns based on provider if not set explicitly
          sync.patterns = lib.mkDefault (
            if config.sync.patterns != [] then config.sync.patterns else
            if config.type == "gmail" then
              [ "INBOX" "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/Trash" "[Gmail]/All Mail" "[Gmail]/Spam" "[Gmail]/Starred" ]
            else
              [ "INBOX" "Sent" "Drafts" "Trash" ]
          );
        };
      }));
      default = {};
      description = "Declaratively configure accounts (Proton Bridge, Gmail, or generic IMAP).";
    };
  };
}
