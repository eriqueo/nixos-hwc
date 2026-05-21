# domains/home/apps/dt/index.nix
#
# dt — DataX time tracker (CLI + TUI + waybar widget)
# Config: ~/.config/dt/config.toml
# Database: ~/.local/share/dt/dt.sqlite
# Invoices: ~/Documents/datax-time/
# Calendar: ~/.local/share/dt/calendar/dt-<id>.ics (per completed session)
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.dt;

  dtPkg = pkgs.callPackage ./parts/package.nix { };

  # Stale-session notifier: prompts the user with action buttons
  # (Clock out / Snooze 15 / Dismiss). Runs detached so the stale-check
  # systemd service exits promptly; this script blocks on user input.
  staleNotifier = pkgs.writeShellScriptBin "dt-stale-notifier" ''
    set -u
    body="''${1:-Session running too long}"
    action=$(${pkgs.libnotify}/bin/notify-send \
      -u critical -a dt \
      --action="clock-out=Clock out" \
      --action="snooze=Snooze 15 min" \
      --action="dismiss=Dismiss" \
      "dt — stale session" "$body" 2>/dev/null || true)
    case "$action" in
      clock-out) ${dtPkg}/bin/dt out -n "auto: stale" >/dev/null 2>&1 || true ;;
      snooze)    ${dtPkg}/bin/dt snooze --minutes 15 >/dev/null 2>&1 || true ;;
      *)         : ;;
    esac
  '';

  configToml = ''
    name = "${cfg.settings.name}"
    rate = ${toString cfg.settings.rate}
    max_session_hours = ${toString cfg.settings.maxSessionHours}
    waybar_poll_seconds = ${toString cfg.settings.waybarPollSeconds}
    pomodoro_minutes = ${toString cfg.pomodoro.intervalMinutes}
  '' + lib.optionalString (cfg.settings.defaultCategory != null) ''
    default_category = "${cfg.settings.defaultCategory}"
  '';

  # PATH that helper scripts and the notifier need for notify-send + dt
  helperPath = lib.makeBinPath [ pkgs.libnotify pkgs.coreutils staleNotifier dtPkg ];
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages = [ dtPkg pkgs.libnotify staleNotifier ];

      xdg.configFile."dt/config.toml".text = configToml;

      # Stale-session check (uses dt-stale-notifier for actionable prompts)
      systemd.user.services.dt-stale-check = lib.mkIf cfg.staleCheck.enable {
        Unit = {
          Description = "dt — stale session check";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${dtPkg}/bin/dt stale-check";
          Environment = [ "PATH=${helperPath}" ];
        };
      };

      systemd.user.timers.dt-stale-check = lib.mkIf cfg.staleCheck.enable {
        Unit = {
          Description = "Periodic stale-session check for dt";
        };
        Timer = {
          OnCalendar = "*:0/${toString cfg.staleCheck.intervalMinutes}";
          Persistent = true;
        };
        Install = { WantedBy = [ "timers.target" ]; };
      };

      # Pomodoro boundary check (fires every minute; cheap DB read + notify if
      # the session crossed another N-minute boundary since last notification)
      systemd.user.services.dt-pomodoro = lib.mkIf cfg.pomodoro.enable {
        Unit = {
          Description = "dt — pomodoro boundary check";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${dtPkg}/bin/dt pomodoro-check";
          Environment = [ "PATH=${helperPath}" ];
        };
      };

      systemd.user.timers.dt-pomodoro = lib.mkIf cfg.pomodoro.enable {
        Unit = {
          Description = "Periodic pomodoro boundary check for dt";
        };
        Timer = {
          OnBootSec = "1min";
          OnUnitActiveSec = "1min";
        };
        Install = { WantedBy = [ "timers.target" ]; };
      };

      # Ensure calendar dir exists on activation so first clock-out doesn't race.
      home.activation.dtCalendarDir = lib.mkIf cfg.calendar.enable
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          mkdir -p $HOME/.local/share/dt/calendar
        '');
    }

    # khal integration — add the dt sessions dir as a calendar so it shows up
    # alongside iCloud events in ikhal/calcure. Gated on both enables.
    (lib.mkIf (cfg.calendar.enable
               && cfg.calendar.integrateKhal
               && (config.hwc.mail.calendar.enable or false)) {
      hwc.mail.calendar.localCalendars."dt-sessions" = {
        path = "${config.home.homeDirectory}/.local/share/dt/calendar";
        color = cfg.calendar.khalColor;
      };
    })

    #========================================================================
    # VALIDATION
    #========================================================================
    {
      assertions = [
        {
          assertion = !cfg.waybar.enable || config.hwc.home.apps.waybar.enable;
          message = ''
            hwc.home.apps.dt.waybar.enable is true but hwc.home.apps.waybar.enable is false.
            Either enable waybar or set hwc.home.apps.dt.waybar.enable = false.
          '';
        }
        {
          assertion = !cfg.hyprland.enable || config.hwc.home.apps.hyprland.enable;
          message = ''
            hwc.home.apps.dt.hyprland.enable is true but hwc.home.apps.hyprland.enable is false.
            Either enable hyprland or set hwc.home.apps.dt.hyprland.enable = false.
          '';
        }
        {
          assertion = !cfg.hyprland.enable || config.hwc.home.apps.kitty.enable;
          message = ''
            dt hyprland keybind opens the TUI in kitty, but hwc.home.apps.kitty.enable is false.
          '';
        }
      ];
    }
  ]);
}
