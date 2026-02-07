# ProtonMail • Behavior part
# Behavioral configuration and settings.
{ lib, pkgs, config, osConfig ? {}, ... }:

{
  files = profileBase: {
    # ProtonMail configuration directory
    ".config/protonmail/desktop/config.json".text = lib.generators.toJSON {} {
      # Basic configuration - ProtonMail handles most settings internally
      minimizeToTray = true;
      enableNotifications = true;
    };
  };
}