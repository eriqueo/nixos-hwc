# REFACTORED file: domains/system/services/session/index.nix
#
# SESSION — User session management and access control.
# Manages sudo, the login manager (greetd), and user lingering.
#
# USAGE:
#   hwc.system.services.session.enable = true;
#   hwc.system.services.session.loginManager.autoLoginUser = "eric";
#   hwc.system.services.session.linger.users = [ "eric" ];

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.session;
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # SUDO CONFIGURATION
    #=========================================================================
    security.sudo = lib.mkIf cfg.sudo.enable {
      enable = true;
      # This is the only option we need now. The rest are secure defaults.
      wheelNeedsPassword = cfg.sudo.wheelNeedsPassword;
    };

    #=========================================================================
    # LOGIN MANAGER (greetd + tuigreet)
    #=========================================================================
    services.greetd = lib.mkIf cfg.loginManager.enable {
      enable = true;
      settings = {
        default_session = {
          user = "greeter";
          command =
            # We hardcode sensible defaults for the greeter arguments.
            let
              args = "--time --remember --remember-user-session --asterisks";
            in
            "${pkgs.tuigreet}/bin/tuigreet ${args} --cmd ${cfg.loginManager.defaultCommand}";
        };
      } // lib.optionalAttrs (cfg.loginManager.autoLoginUser != null) {
        # The initial_session block is only added if autoLoginUser is set.
        initial_session = {
          user = cfg.loginManager.autoLoginUser;
          command = cfg.loginManager.defaultCommand;
        };
      };
    };

    # Force disable other common display managers to prevent conflicts.
    services.displayManager.gdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.displayManager.sddm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.xserver.displayManager.lightdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);

    #=========================================================================
    # USER LINGERING CONFIGURATION
    #=========================================================================
    # This applies the 'linger = true' setting to the specified list of users.
    users.users = lib.mkIf cfg.linger.enable (
      lib.genAttrs cfg.linger.users (_: { linger = true; })
    );

    #=========================================================================
    # CO-LOCATED PACKAGES
    #=========================================================================
    # The tuigreet package is now bundled with the service that uses it.
    environment.systemPackages = lib.mkIf cfg.loginManager.enable [ pkgs.tuigreet ];

    #=========================================================================
    # VALIDATION & WARNINGS
    #=========================================================================
    assertions = [
      {
        assertion = (cfg.loginManager.autoLoginUser == null)
                 || (lib.hasAttr cfg.loginManager.autoLoginUser config.users.users);
        message = "Login manager: autoLoginUser '${cfg.loginManager.autoLoginUser}' is not a defined user.";
      }
      {
        assertion = (!cfg.linger.enable)
                 || (lib.all (u: lib.hasAttr u config.users.users) cfg.linger.users);
        message = "Lingering: one or more users in the linger list are not defined users.";
      }
    ];

    warnings = lib.optionals (cfg.sudo.enable && !cfg.sudo.wheelNeedsPassword) [
      "SECURITY NOTICE: Passwordless sudo for the 'wheel' group is active. This is convenient but reduces security."
    ];
  };
}
