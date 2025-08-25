# nixos-hwc/modules/security/emergency-access.nix
#
# HWC Emergency Root Access (Charter v3)
# Provides a temporary, password-protected root account for recovery.

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

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      users.users.root.initialPassword = cfg.password;
      services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
      assertions = [{
        assertion = cfg.password != null && cfg.password != "";
        message = "[hwc.security.emergencyAccess] is enabled, but no password is set. This is a misconfiguration.";
      }];
    })

    (lib.mkIf cfg.enable {
      warnings = [ ''
        ##################################################################
        # SECURITY WARNING: EMERGENCY ROOT ACCESS IS ACTIVE              #
        # The root user has a password set in your configuration.nix.    #
        # Disable this feature in your machine config once stable.       #
        ##################################################################
      '' ];
    })
  ];
}
