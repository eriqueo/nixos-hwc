# ProtonPass • Behavior part
# Behavioral configuration and settings.
{ lib, pkgs, config, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.protonPass;
in
{
  files = profileBase: {
    # ProtonPass configuration
    ".config/protonpass/config.json".text = lib.generators.toJSON {} {
      # Basic configuration
      minimizeToTray = true;
      enableNotifications = true;
      autoLock = true;
      autoLockTimeout = 900; # 15 minutes
      browserIntegration = cfg.browserIntegration;
    };
  };
}