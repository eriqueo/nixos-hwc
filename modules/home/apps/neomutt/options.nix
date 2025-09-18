{ lib, ... }:

{
  options.features.neomutt = {
    enable = lib.mkEnableOption "Enable NeoMutt and related mail tooling";

    materials = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Resolved security/materials view from system lane.";
    };

    adapter = lib.mkOption {
      type = lib.types.enum [ "default" "old-dog" ];
      default = "default";
      description = "Theme adapter to use for NeoMutt.";
    };

    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
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
          type = lib.mkOption {
            type = lib.types.enum [ "proton-bridge" "gmail" ];
            default = "proton-bridge";
            description = "Account backend type.";
          };
          login = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "IMAP/SMTP login. If empty, generators will fall back appropriately.";
          };
          bridgeUsername = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Deprecated (Proton Bridge local username). Prefer 'login'.";
          };
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
          maildirName = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "Top-level Maildir name under ~/Maildir (e.g. 'proton', 'gmail-personal').";
          };
          sync = {
            patterns = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "INBOX" "Sent" "Drafts" "Trash" ];
              description = "mbsync channel patterns to sync.";
            };
          };
          send = {
            msmtpAccount = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "msmtp 'account' name to emit for this identity.";
            };
          };
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
