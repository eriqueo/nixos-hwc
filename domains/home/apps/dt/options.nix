# domains/home/apps/dt/options.nix
#
# Namespace: hwc.home.apps.dt.*
{ lib, ... }:
{
  options.hwc.home.apps.dt = {
    enable = lib.mkEnableOption "dt — DataX time tracker (CLI + TUI)";

    settings = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Eric O'Keefe";
        description = "Name to print on invoices.";
      };
      rate = lib.mkOption {
        type = lib.types.number;
        default = 40;
        description = "Hourly rate in dollars.";
      };
      maxSessionHours = lib.mkOption {
        type = lib.types.number;
        default = 10;
        description = "Hours before an open clock-in is considered stale.";
      };
      waybarPollSeconds = lib.mkOption {
        type = lib.types.number;
        default = 30;
        description = "How often waybar polls `dt status --waybar`.";
      };
      defaultCategory = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Skip the clock-in category prompt by defaulting to this.";
      };
    };

    waybar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add the custom/dt widget to waybar (requires hwc.home.apps.waybar.enable).";
      };
    };

    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Bind SUPER+T to open the dt TUI (requires hwc.home.apps.hyprland.enable).";
      };
      toggleBind = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "SUPER SHIFT,T";
        example = "SUPER SHIFT,T";
        description = ''
          Hyprland modifier+key spec for `dt toggle` (click-free clock in/out).
          Set to null to disable. Format: "<MODS>,<KEY>" — see hyprland bind syntax.
        '';
      };
    };

    pomodoro = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Send a notification at each pomodoro interval while clocked in.";
      };
      intervalMinutes = lib.mkOption {
        type = lib.types.int;
        default = 25;
        description = "Notify every N minutes of continuous active session.";
      };
    };

    calendar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Write each completed session as an .ics event under ~/.local/share/dt/calendar/.";
      };
      integrateKhal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Inject a `dt-sessions` calendar into khal so sessions appear in ikhal/calcure
          alongside iCloud events. Requires hwc.mail.calendar.enable.
        '';
      };
      khalColor = lib.mkOption {
        type = lib.types.str;
        default = "dark cyan";
        description = "khal display color for the dt calendar.";
      };
    };

    staleCheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run `dt stale-check` on a systemd user timer for desktop notifications.";
      };
      intervalMinutes = lib.mkOption {
        type = lib.types.int;
        default = 15;
        description = "How often the stale-check timer fires.";
      };
    };
  };
}
