# NEW file: domains/system/services/session/options.nix
{ lib, config, ... }:

{
  options.hwc.system.services.session = {
    # The master switch for all session-related services.
    enable = lib.mkEnableOption "Enable user session management (sudo, login manager, lingering)";

    # --- Sudo Sub-Module ---
    sudo = {
      enable = lib.mkEnableOption "Enable sudo configuration";

      # This is the most important sudo toggle.
      wheelNeedsPassword = lib.mkOption {
        type = lib.types.bool;
        default = false; # Sensible default for a single-user workstation.
        description = "Whether members of the 'wheel' group must enter a password for sudo.";
      };
    };

    # --- Login Manager Sub-Module ---
    loginManager = {
      enable = lib.mkEnableOption "Enable greetd + tuigreet login manager";

      # This is a key per-machine setting.
      autoLoginUser = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null; # Default to no autologin for security.
        example = "eric";
        description = "User to automatically log in. Set to null to disable autologin.";
      };

      # This is also machine/DE specific.
      defaultCommand = lib.mkOption {
        type = lib.types.str;
        default = "Hyprland";
        description = "Default session command (e.g., 'Hyprland', 'gnome', 'plasma')";
      };
    };

    # --- Linger Sub-Module ---
    linger = {
      enable = lib.mkEnableOption "Enable user lingering";

      # This is the only setting needed for linger.
      users = lib.mkOption {
        type = with lib.types; listOf str;
        default = [];
        example = [ "eric" ];
        description = "List of users to enable linger for.";
      };
    };
  };
}
