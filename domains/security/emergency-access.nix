# HWC Charter Module/domains/security/emergency-access.nix
#
# HWC Emergency Root Access (Charter v3)
# Provides a temporary, password-protected root account for recovery.
#
# DEPENDENCIES (Upstream):
#   - agenix.nixosModules.default (if using passwordFile/hashedPasswordFile via age)
#
# USED BY (Downstream):
#   - profiles/security.nix (orchestrates security posture)
#   - machines/*/config.nix (facts: enable + secret wiring)
#
# USAGE (preferred with agenix):
#   age.secrets."emergency-password".file = ./secrets/emergency-password.age;
#   hwc.security.emergencyAccess = {
#     enable = true;
#     hashedPasswordFile = config.age.secrets."emergency-password".path;
#   };

{ config, lib, ... }:

let
  cfg = config.hwc.security.emergencyAccess;

  hasHPF = cfg.hashedPasswordFile != null;
  hasHP  = cfg.hashedPassword     != null;
  hasPF  = cfg.passwordFile       != null;
  hasP   = cfg.password           != null;

  exactlyOne =
    (lib.length (lib.filter (x: x) [ hasHPF hasHP hasPF hasP ])) == 1;
in
{
  #============================================================================
  # OPTIONS – Interface (no secrets hardcoded)
  #============================================================================
  options.hwc.security.emergencyAccess = {
    enable = lib.mkEnableOption "Emergency root password access (temporary)";

    # Plaintext (discouraged; becomes initialPassword)
    password = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "PLAINTEXT emergency password (applied as initialPassword). Prefer hashed/passwordFile.";
    };

    # Plaintext file (good with agenix: config.age.secrets.<name>.path)
    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to PLAINTEXT password file (e.g. agenix secret path).";
    };

    # Hashed inputs (preferred)
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
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [{
        assertion = exactlyOne;
        message =
          "[hwc.security.emergencyAccess] enabled, but you must provide exactly one of: "
          + "hashedPasswordFile, hashedPassword, passwordFile, or password.";
      }];

      # Allow root password auth while emergency access is active
      services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

      warnings = [ ''
        ##################################################################
        # SECURITY WARNING: EMERGENCY ROOT ACCESS IS ACTIVE              #
        # Disable `hwc.security.emergencyAccess.enable` when finished.   #
        ##################################################################
      '' ];
    }

    # Pick exactly one credential source without splicing attrsets
    (lib.mkIf hasHPF { users.users.root.hashedPasswordFile = cfg.hashedPasswordFile; })
    (lib.mkIf hasHP  { users.users.root.hashedPassword     = cfg.hashedPassword;     })
    (lib.mkIf hasPF  { users.users.root.passwordFile       = cfg.passwordFile;       })
    (lib.mkIf hasP   {
      users.users.root.initialPassword = cfg.password;
      warnings = [ ''
        WARNING: Using `initialPassword` (plaintext). This only applies on first
        activation; later changes won’t update root. Prefer hashedPassword{,File}.
      '' ];
    })
  ]);
}
