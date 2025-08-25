# nixos-hwc/modules/security/emergency-access.nix
#
# HWC Emergency Root Access (Charter v3)
# Provides a temporary, password-protected root account for recovery.
#
# DEPENDENCIES (Upstream):
#   - agenix.nixosModules.default (if using passwordFile/hashedPasswordFile via age)
#
# USED BY (Downstream):
#   - profiles/security.nix (orchestrates security posture)
#   - machines/*/config.nix (machine facts: enable + secret wiring)
#
# USAGE (recommended with agenix):
#   # secrets/emergency-password.age created with `agenix`
#   age.secrets."emergency-password".file = ./secrets/emergency-password.age;
#   hwc.security.emergencyAccess = {
#     enable = true;
#     hashedPasswordFile = config.age.secrets."emergency-password".path;
#   };

{ config, lib, ... }:

let
  cfg = config.hwc.security.emergencyAccess;

  chosenCred =
    if cfg.hashedPasswordFile != null then
      { attr = { users.users.root.hashedPasswordFile = cfg.hashedPasswordFile; }; warn = null; }
    else if cfg.hashedPassword != null then
      { attr = { users.users.root.hashedPassword     = cfg.hashedPassword;     }; warn = null; }
    else if cfg.passwordFile != null then
      { attr = { users.users.root.passwordFile       = cfg.passwordFile;       }; warn = null; }
    else if cfg.password != null then
      { attr = { users.users.root.initialPassword    = cfg.password;           };
        warn = ''
          WARNING: emergencyAccess is using `initialPassword` (plaintext).
          This only applies on first activation; subsequent changes won’t update root.
          Prefer `hashedPassword{,File}` via agenix.
        '';
      }
    else
      { attr = {}; warn = null; };
in
{
  #============================================================================
  # OPTIONS – Interface (no secrets hardcoded)
  #============================================================================
  options.hwc.security.emergencyAccess = {
    enable = lib.mkEnableOption "Emergency root password access (temporary)";

    password = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "PLAINTEXT emergency password (applied as initialPassword). Prefer hashed/passwordFile.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to PLAINTEXT password file (e.g. agenix secret path).";
    };

    hashedPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Hashed password (e.g. mkpasswd -m sha-512). Preferred.";
    };

    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing a hashed password. Preferred.";
    };
  };

  #============================================================================
  # IMPLEMENTATION – Apply when enabled; assert invariant
  #============================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [{
        assertion =
          (cfg.hashedPasswordFile != null)
          || (cfg.hashedPassword != null)
          || (cfg.passwordFile != null)
          || (cfg.password != null);
        message = "[hwc.security.emergencyAccess] is enabled, but no password/secret was provided.";
      }];

      # Allow root login while emergency access is active
      services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
    })

    (lib.mkIf cfg.enable chosenCred.attr)

    (lib.mkIf (cfg.enable && chosenCred.warn != null) {
      warnings = [ chosenCred.warn ];
    })

    (lib.mkIf cfg.enable {
      warnings = [ ''
        ##################################################################
        # SECURITY WARNING: EMERGENCY ROOT ACCESS IS ACTIVE              #
        # Disable `hwc.security.emergencyAccess.enable` when finished.   #
        ##################################################################
      '' ];
    })
  ];
}
