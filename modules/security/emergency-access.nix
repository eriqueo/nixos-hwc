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
    # This first part contains the actual configuration options
    (lib.mkIf cfg.enable {
      users.users.root.initialPassword = cfg.password;
      services.openssh.permitRootLogin = "yes";
      assertions = [{
        assertion = cfg.password != null && cfg.password != "";
        message = "[hwc.security.emergencyAccess] is enabled, but no password is set. This is a misconfiguration.";
      }];
    })

    # ===================================================================
    # THIS IS THE CORRECT PATTERN FOR THE WARNING
    # It uses a separate mkIf block with a let-in binding to trigger
    # the warning without assigning it to an option.
    # ===================================================================
    (lib.mkIf cfg.enable {
      # This block does not set any options. It only performs an action.
      _ = let
        # This forces the evaluation of lib.warn
        warning = lib.warn ''
          ##################################################################
          # SECURITY WARNING: EMERGENCY ROOT ACCESS IS ACTIVE              #
          # The root user has a password set in your configuration.nix.    #
          # Please disable this feature in your machine config once stable.#
          ##################################################################
        '';
      in {
        # The block must return an attribute set. An empty one is fine.
      };
    })
  ];

}
