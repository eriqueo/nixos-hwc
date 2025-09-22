# nixos-h../domains/system/services/session.nix
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
  #### OPTIONS ###############################################################
  options.hwc.system.services.session = {
    enable = lib.mkEnableOption "User session management (sudo, greetd, lingering)";

    sudo = {
      enable = lib.mkEnableOption "Configure sudo (wheel policy, optional extra rules)";

      wheelNeedsPassword = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether members of wheel must enter a password for sudo.";
      };

      enableExtraRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable extra NOPASSWD rules for specific users.";
      };

      extraUsers = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "eric" ];
        description = "Users to grant NOPASSWD sudo to (when enableExtraRules = true).";
      };
    };

    loginManager = {
      enable = lib.mkEnableOption "Enable greetd + tuigreet login manager";

      defaultUser = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Default user for autologin (if enabled).";
      };

      defaultCommand = lib.mkOption {
        type = lib.types.str;
        default = "Hyprland";
        description = "Default session command executed after login.";
      };

      autoLogin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically log in defaultUser into defaultCommand.";
      };

      showTime = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show time in tuigreet.";
      };

      greeterExtraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "--remember" "--remember-user-session" "--asterisks" ];
        description = "Additional tuigreet CLI arguments.";
      };
    };

    linger = {
      enable = lib.mkEnableOption "Enable lingering for selected users (keeps user systemd running without login)";

      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "eric" ];
        description = "Users to enable linger for (so user timers/services run when logged out).";
      };
    };
  };

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
