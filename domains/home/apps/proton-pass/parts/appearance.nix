# ProtonPass • Appearance part
# Theming and visual configuration.
{ lib, pkgs, config, osConfig ? {}, ... }:

{
  files = profileBase: {
    # Proton Pass Electron app config (note: space in directory name)
    # This forces dark mode; window position will reset on rebuild
    ".config/Proton Pass/config.json".text = lib.generators.toJSON {} {
      "__internal__" = {
        migrations = {
          version = "1.33.5";
        };
      };
      theme = "dark";
      windowConfig = {
        width = 1258;
        height = 1492;
        maximized = true;
        zoomLevel = 0;
      };
    };
  };
}