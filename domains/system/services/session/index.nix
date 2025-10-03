{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.session;
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # SUDO CONFIGURATION
    #=========================================================================

    security.sudo = lib.mkIf cfg.sudo.enable {
      enable = true;
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
            let
              args = "--time --remember --remember-user-session --asterisks";
            in
            "${pkgs.tuigreet}/bin/tuigreet ${args} --cmd ${cfg.loginManager.defaultCommand}";
        };
      } // lib.optionalAttrs (cfg.loginManager.autoLoginUser != null) {
        initial_session = {
          user = cfg.loginManager.autoLoginUser;
          command = cfg.loginManager.defaultCommand;
        };
      };
    };

    services.displayManager.gdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.displayManager.sddm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.xserver.displayManager.lightdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);

    #=========================================================================
    # USER LINGERING
    #=========================================================================

    users.users = lib.mkIf cfg.linger.enable (
      lib.genAttrs cfg.linger.users (_: { linger = true; })
    );

    #=========================================================================
    # CO-LOCATED PACKAGES
    #=========================================================================

    environment.systemPackages = lib.mkIf cfg.loginManager.enable [ pkgs.tuigreet ];

    #=========================================================================
    # VALIDATION
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
      "SECURITY NOTICE: Passwordless sudo for the 'wheel' group is active."
    ];
  };
}
