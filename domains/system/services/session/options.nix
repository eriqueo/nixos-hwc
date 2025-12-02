{ lib, ... }:

{
  options.hwc.system.services.session = {
    # Master toggle
    enable = lib.mkEnableOption "Enable user session management (sudo, login manager, lingering)";

    # --- Sudo Sub-Module ---
    sudo = {
      enable = lib.mkEnableOption "Enable sudo configuration";

      wheelNeedsPassword = lib.mkOption {
        type = lib.types.bool;
        default = false; # Single-user workstation default
        description = "Whether members of the 'wheel' group must enter a password for sudo.";
      };

      extraRules = lib.mkOption {
        type = with lib.types; listOf attrs;
        default = [];
        example = [
          { users = [ "eric" ]; commands = [ { command = "/run/current-system/sw/bin/podman"; options = [ "NOPASSWD" ]; } ]; }
        ];
        description = "Additional sudo rules for specific commands without password.";
      };
    };

    # --- Login Manager Sub-Module ---
    loginManager = {
      enable = lib.mkEnableOption "Enable greetd + tuigreet login manager";

      autoLoginUser = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "eric";
        description = "User to automatically log in. Set null to disable autologin.";
      };

      defaultCommand = lib.mkOption {
        type = lib.types.str;
        default = "Hyprland";
        description = "Default session command (e.g. 'Hyprland', 'gnome', 'plasma').";
      };
    };

    # --- Linger Sub-Module ---
    linger = {
      enable = lib.mkEnableOption "Enable user lingering";

      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [];
        example = [ "eric" ];
        description = "List of users to enable linger for.";
      };
    };
  };
}
