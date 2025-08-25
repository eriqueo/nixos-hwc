# nixos-hwc/modules/security/emergency-access.nix
#
# HWC Emergency Root Access (Charter v3)
# Provides a temporary, password-protected root account for recovery.
#
# DEPENDENCIES: None
# USED BY: profiles/security.nix, machines/*/config.nix
# USAGE:
#   hwc.security.emergencyAccess.enable = true;
#   hwc.security.emergencyAccess.password = "a-very-strong-password";

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.security.emergencyAccess;
in
{
  options.hwc.security.emergencyAccess = {
    enable = lib.mkEnableOption "emergency root password access";
    password = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The password for the root user. SET THIS for emergency access.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Set the initial password for the 'root' user.
    users.users.root.initialPassword = cfg.password;

    # Allow root login via SSH if SSH is enabled.
    services.openssh.permitRootLogin = "yes";

    # CRITICAL: Fail the build if this is enabled without a password.
    assertions = [{
      assertion = cfg.password != null && cfg.password != "";
      message = "[hwc.security.emergencyAccess] is enabled, but no password is set. This is a misconfiguration.";
    }];

    # Prominently warn the user that this insecure feature is active.
    system.nixos.warning =[ ''
      ##################################################################
      # SECURITY WARNING: EMERGENCY ROOT ACCESS IS ACTIVE              #
      # The root user has a password set in your configuration.nix.    #
      # Please disable this feature in your machine config once stable.#
      ##################################################################
    ''];
  };
}
