# nixos-hwc/modules/system/services/session.nix
#
# SESSION - User session management and access control
# Combines login manager and sudo configuration for unified session access control
#
# DEPENDENCIES (Upstream):
#   - config.hwc.system.users.* (modules/system/core/eric.nix)
#
# USED BY (Downstream):
#   - profiles/base.nix (enables via hwc.system.services.session.sudo)
#   - profiles/workstation.nix (enables via hwc.system.services.session.loginManager)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../modules/system/services/session.nix
#
# USAGE:
#   hwc.system.services.session.sudo.enable = true;
#   hwc.system.services.session.loginManager.enable = true;
#   hwc.system.services.session.loginManager.defaultUser = "eric";

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.session;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================

  options.hwc.system.services.session = {
    enable = lib.mkEnableOption "user session management and access control";

    # Sudo privilege escalation configuration
    sudo = {
      enable = lib.mkEnableOption "sudo privilege escalation configuration";
      
      wheelNeedsPassword = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether wheel group members need password for sudo";
      };
      
      enableExtraRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable custom sudo rules beyond wheel group";
      };
      
      extraUsers = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "eric" ];
        description = "Users to grant additional sudo privileges";
      };
    };

    # Login manager configuration
    loginManager = {
      enable = lib.mkEnableOption "Greetd login manager with TUI greeter";

      # Default session settings
      defaultUser = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Default user for initial session";
      };

      defaultCommand = lib.mkOption {
        type = lib.types.str;
        default = "Hyprland";
        description = "Default window manager/desktop environment command";
      };

      # Auto-login settings
      autoLogin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable automatic login for default user";
      };

      # Greeter settings
      showTime = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show time in TUI greeter";
      };

      # Additional greeter options
      greeterExtraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional arguments to pass to tuigreet";
        example = [ "--asterisks" "--remember" "--remember-user-session" ];
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================

  config = lib.mkIf cfg.enable {

    #=========================================================================
    # SUDO PRIVILEGE ESCALATION
    #=========================================================================

    # Core sudo configuration
    security.sudo = lib.mkIf cfg.sudo.enable {
      enable = true;
      wheelNeedsPassword = cfg.sudo.wheelNeedsPassword;
      
      # Custom rules for specific users (optional)
      extraRules = lib.mkIf cfg.sudo.enableExtraRules [
        {
          users = cfg.sudo.extraUsers;
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

    #=========================================================================
    # LOGIN MANAGER CONFIGURATION
    #=========================================================================

    # Greetd service configuration
    services.greetd = lib.mkIf cfg.loginManager.enable {
      enable = true;
      settings = {
        # Default greeter session
        default_session = {
          user = "greeter";
          command = let
            timeArg = lib.optionalString cfg.loginManager.showTime "--time";
            extraArgs = lib.concatStringsSep " " cfg.loginManager.greeterExtraArgs;
            allArgs = lib.concatStringsSep " " (lib.filter (s: s != "") [ timeArg extraArgs ]);
          in "${pkgs.tuigreet}/bin/tuigreet ${allArgs} --cmd ${cfg.loginManager.defaultCommand}";
        };

        # Auto-login session (if enabled)
      } // lib.optionalAttrs cfg.loginManager.autoLogin {
        initial_session = {
          user = cfg.loginManager.defaultUser;
          command = cfg.loginManager.defaultCommand;
        };
      };
    };

    # Install greeter package
    environment.systemPackages = lib.mkIf cfg.loginManager.enable (with pkgs; [
      tuigreet  # TUI greeter for greetd
    ]);

    # Disable other display managers (using correct NixOS 24.05+ option names)
    services.displayManager.gdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);
    services.xserver.displayManager.lightdm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);  # lightdm not moved yet
    services.displayManager.sddm.enable = lib.mkIf cfg.loginManager.enable (lib.mkForce false);

    #=========================================================================
    # VALIDATION AND WARNINGS
    #=========================================================================

    # Validation: Check default user exists
    assertions = [
      {
        assertion = !cfg.loginManager.enable || (config.users.users ? ${cfg.loginManager.defaultUser});
        message = "Login manager default user '${cfg.loginManager.defaultUser}' does not exist";
      }
      {
        assertion = !cfg.sudo.enableExtraRules || (cfg.sudo.extraUsers != []);
        message = "Extra sudo rules enabled but no users specified in extraUsers";
      }
    ];

    # Warning when passwordless sudo is enabled
    warnings = lib.optionals (cfg.sudo.enable && (!cfg.sudo.wheelNeedsPassword || cfg.sudo.enableExtraRules)) [
      ''
        ##################################################################
        # SECURITY NOTICE: PASSWORDLESS SUDO IS ACTIVE                   #
        # Current sudo configuration allows privilege escalation without  #
        # password prompts. This is convenient but reduces security.      #
        ##################################################################
      ''
    ];
  };
}