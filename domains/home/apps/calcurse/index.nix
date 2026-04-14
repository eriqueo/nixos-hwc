# domains/home/apps/calcurse/index.nix
#
# calcurse — TUI calendar and scheduling application
# Config: ~/.config/calcurse/conf (XDG, supported since calcurse 3.0)
# Theme: terminal color names mapped to Nord palette via kitty's ANSI assignments
#   "blue"    → terminal color4 → Nord primary accent #88c0d0
#   "default" → transparent (preserves Nord bg from terminal)
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.calcurse;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.calcurse = {
    enable = lib.mkEnableOption "calcurse TUI calendar and task scheduler";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.calcurse ];

    xdg.desktopEntries.calcurse = {
      name = "calcurse";
      comment = "Calendar and scheduling application";
      exec = "kitty --title calcurse calcurse";
      terminal = false;
      categories = [ "Office" "Calendar" ];
    };

    # calcurse uses XDG config dir since v3.0
    xdg.configFile."calcurse/conf".text = ''
      appearance.calendarview=monthly
      appearance.layout=1
      appearance.notifybar=yes
      appearance.sidebarwidth=0
      appearance.theme=blue on default
      general.autosave=yes
      general.autosaveinterval=0
      general.confirmdelete=yes
      general.confirmquit=no
      general.firstdayofweek=monday
      general.periodicsave=0
      general.progressbar=yes
      general.systemdialog=yes
      format.inputdatefmt=1
      format.notifydate=%a %F
      format.notifytime=%T
      notification.warning=300
      notification.command=
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [];
  };
}
