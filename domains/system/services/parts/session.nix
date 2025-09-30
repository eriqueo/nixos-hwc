# HWC Charter Module/domains/system/services/session.nix
#
# SESSION — User session management and access control
# - Sudo policy (wheel, extra NOPASSWD rules)
# - Login manager (greetd + tuigreet)
# - User lingering (keep user systemd running while logged out)
#
# Upstream deps:
#   - users defined elsewhere (e.g., modules/system/users/*)
#
# Downstream usage:
#   - profiles/base.nix:
#       hwc.system.services.session = {
#         enable = true;
#         sudo.enable = true;
#         linger = { enable = true; users = [ "eric" ]; };
#       };
#   - profiles/sys.nix:
#       hwc.system.services.session.loginManager = {
#         enable = true;
#         defaultUser = "eric";
#         defaultCommand = "Hyprland";
#         autoLogin = true;
#       };

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.session;
in
{
  #### IMPLEMENTATION ########################################################
  config = lib.mkIf cfg.enable {

    # ---------------- SUDO ----------------
    security.sudo = lib.mkIf cfg.sudo.enable {
      enable = true;
      wheelNeedsPassword = cfg.sudo.wheelNeedsPassword;

      extraRules = lib.mkIf cfg.sudo.enableExtraRules [
        {
          users = cfg.sudo.extraUsers;
          commands = [{
            command = "ALL";
            options = [ "NOPASSWD" ];
          }];
        }
      ];
    };

    # ---------------- LOGIN MANAGER (greetd + tuigreet) ----------------
    services.greetd = lib.mkIf cfg.loginManager.enable {
      enable = true;
      settings = {
        default_session = {
          user = "greeter";
          command =
            let
              timeArg   = lib.optionalString cfg.loginManager.showTime "--time";
              extraArgs = lib.concatStringsSep " " cfg.loginManager.greeterExtraArgs;
              args      = lib.concatStringsSep " " (lib.filter (s: s != "") [ timeArg extraArgs ]);
            in "${pkgs.tuigreet}/bin/tuigreet ${args} --cmd ${cfg.loginManager.defaultCommand}";
        };
      } // lib.optionalAttrs cfg.loginManager.autoLogin {
        initial_session = {
          user = cfg.loginManager.defaultUser;
          command = cfg.loginManager.defaultCommand;
        };
      };
    };

    # Provide greeter package
    environment.systemPackages = lib.mkIf cfg.loginManager.enable [ pkgs.tuigreet ];

    # Disable other display managers
    # GDM/SDDM (newer paths)
    services.displayManager.gdm.enable  = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.displayManager.sddm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);

    # LightDM (still under the xserver namespace on your channel)
    services.xserver.displayManager.lightdm.enable =
      lib.mkIf cfg.loginManager.enable (lib.mkForce false);

    # ---------------- LINGERING (per-user) ----------------
    # NixOS doesn't have services.logind.lingerUsers; it's per-user:
    # users.users.<name>.linger = true;
    users.users =
      lib.mkIf cfg.linger.enable
        (lib.genAttrs cfg.linger.users (_: { linger = true; }));

    #### VALIDATION & WARNINGS ###############################################
    assertions =
      [
        # If loginManager is enabled, defaultUser must be declared in users.users.
        {
          assertion = (!cfg.loginManager.enable)
                   || (lib.hasAttr cfg.loginManager.defaultUser config.users.users);
          message = "Login manager: defaultUser '${cfg.loginManager.defaultUser}' is not defined in users.users.";
        }
        # If lingering is enabled, all listed users must exist.
        {
          assertion = (!cfg.linger.enable)
                   || (lib.all (u: lib.hasAttr u config.users.users) cfg.linger.users);
          message = "Lingering: one or more users in hwc.system.services.session.linger.users are not defined in users.users.";
        }
        # If extra sudo rules are enabled, at least one user must be listed.
        {
          assertion = (!cfg.sudo.enableExtraRules) || (cfg.sudo.extraUsers != []);
          message = "Sudo: enableExtraRules is true but extraUsers is empty.";
        }
      ];

    warnings = lib.optionals (cfg.sudo.enable && (!cfg.sudo.wheelNeedsPassword || cfg.sudo.enableExtraRules)) [
      ''
        SECURITY NOTICE: passwordless sudo is active (wheelNeedsPassword = ${toString cfg.sudo.wheelNeedsPassword};
        extra NOPASSWD rules = ${toString cfg.sudo.enableExtraRules}). This is convenient but reduces security.
      ''
    ];
  };
}
