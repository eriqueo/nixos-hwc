# domains/system/services/options.nix
#
# Consolidated options for system services subdomain
# Charter-compliant: ALL services options defined here

{ lib, config, ... }:

{
  #============================================================================
  # BEHAVIOR OPTIONS (Input devices & audio)
  #============================================================================
  options.hwc.system.services.behavior = {
    enable = lib.mkEnableOption "system input behavior and audio configuration";

    keyboard = {
      enable = lib.mkEnableOption "universal keyboard mapping";
      universalFunctionKeys = lib.mkEnableOption "standardize F-keys across all keyboards";
    };

    mouse = {
      enable = lib.mkEnableOption "universal mouse configuration";
    };

    touchpad = {
      enable = lib.mkEnableOption "universal touchpad configuration";
    };

    audio = {
      enable = lib.mkEnableOption "PipeWire audio system";
    };
  };

  #============================================================================
  # SESSION OPTIONS (Sudo, login manager, lingering)
  #============================================================================
  options.hwc.system.services.session = {
    enable = lib.mkEnableOption "User session management (sudo, greetd, lingering)";

    sudo = {
      enable = lib.mkEnableOption "Configure sudo (wheel policy, optional extra rules)";

      wheelNeedsPassword = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether members of wheel must enter a password for sudo";
      };

      enableExtraRules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable extra NOPASSWD rules for specific users";
      };

      extraUsers = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "eric" ];
        description = "Users to grant NOPASSWD sudo to (when enableExtraRules = true)";
      };
    };

    loginManager = {
      enable = lib.mkEnableOption "Enable greetd + tuigreet login manager";

      defaultUser = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Default user for autologin (if enabled)";
      };

      defaultCommand = lib.mkOption {
        type = lib.types.str;
        default = "Hyprland";
        description = "Default session command executed after login";
      };

      autoLogin = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically log in defaultUser into defaultCommand";
      };

      showTime = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show time in tuigreet";
      };

      greeterExtraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "--remember" "--remember-user-session" "--asterisks" ];
        description = "Additional tuigreet CLI arguments";
      };
    };

    linger = {
      enable = lib.mkEnableOption "Enable lingering for selected users (keeps user systemd running without login)";

      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "eric" ];
        description = "Users to enable linger for (so user timers/services run when logged out)";
      };
    };
  };


  #============================================================================
  # NETWORKING OPTIONS (SSH, Tailscale, Firewall, DNS)
  #============================================================================
 
}
