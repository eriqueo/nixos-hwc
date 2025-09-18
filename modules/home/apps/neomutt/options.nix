# modules/home/apps/neomutt/options.nix
{ lib, ... }:

{
  options.features.neomutt = {
    enable = lib.mkEnableOption "Enable NeoMutt and related mail tooling";

    # Provided by your system lane; leave as attrs passthrough
    materials = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Resolved security/materials view from system lane.";
    };

    # Declarative accounts
    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          # Identity
          name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Internal account name (used for Maildir name defaults, etc.).";
          };
          realName = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Full name for outgoing emails.";
          };
          address = lib.mkOption {
            type = lib.types.str;
            description = "Email address (From:).";
            example = "eric@iheartwoodcraft.com";
          };

          # Backend/provider
          type = lib.mkOption {
            type = lib.types.enum [ "proton-bridge" "gmail" ];
            default = "proton-bridge";
            description = "Account backend type.";
          };

          # Login: leave empty to let generators fall back (bridge user / address)
          login = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "IMAP/SMTP login. If empty, generators will fall back appropriately.";
          };

          # DEPRECATED: kept for transitional use only; not used if login is set.
          bridgeUsername = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Deprecated (Proton Bridge local username). Prefer 'login'.";
            # Optional: visible = false;
          };

          # Password source
          password = {
            mode = lib.mkOption {
              type = lib.types.enum [ "pass" "agenix" "command" ];
              default = "pass";
              description = "Where to fetch the password.";
            };
            pass = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "pass path, e.g. 'email/proton/bridge'. Used when mode = 'pass'.";
            };
            agenix = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Absolute path to a decrypted secret file (e.g. /run/agenix/...). Used when mode = 'agenix'.";
            };
            command = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Shell command that prints the password. Used when mode = 'command'.";
            };
          };

          # Maildir naming
          maildirName = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Top-level Maildir name under ~/Maildir (e.g. 'proton', 'gmail-personal').";
          };

          # Sync configuration
          sync = {
            patterns = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "INBOX" "Sent" "Drafts" "Trash" ];
              description = "mbsync channel patterns to sync.";
            };
          };

          # Sending configuration
          send = {
            msmtpAccount = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "msmtp 'account' name to emit for this identity.";
            };
          };

          # Default sender selection
          primary = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this is the default sender (msmtp 'account default').";
          };
        };
      }));
      default = {};
      description = "Declaratively configure mail accounts.";
    };
  };
}
